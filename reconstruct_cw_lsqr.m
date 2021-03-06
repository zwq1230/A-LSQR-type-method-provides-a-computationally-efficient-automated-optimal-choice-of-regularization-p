function [fwd_mesh,pj_error] = reconstruct_cw_lsqr(fwd_fn,...
    recon_basis,...
    frequency,...
    data_fn,...
    iteration,...
    lambda,...
    output_fn,...
    filter_n)


tic;

% load fine mesh for fwd solve
fwd_mesh = load_mesh(fwd_fn);

if ischar(recon_basis)
    recon_mesh = load_mesh(recon_basis);
    [fwd_mesh.fine2coarse,...
        recon_mesh.coarse2fine] = second_mesh_basis(fwd_mesh,recon_mesh);
else
    [fwd_mesh.fine2coarse,recon_mesh] = pixel_basis(recon_basis,fwd_mesh);
end

% read data
anom = load_data(data_fn);
% anom = load(data_fn);
anom = log(anom.paa(:,1));
% anom = log(anom(:,1));
% anom = load(data_fn);
% anom = log(anom(:,1));
% $$$ anom(:,1) = log(anom(:,1));
% $$$ anom(:,2) = anom(:,2)/180.0*pi;
% $$$ anom(find(anom(:,2)<0),2) = anom(find(anom(:,2)<0),2) + (2*pi);
% $$$ anom(find(anom(:,2)>(2*pi)),2) = anom(find(anom(:,2)>(2*pi)),2) - (2*pi);
% $$$ anom = reshape(anom',length(anom)*2,1);

% Initiate projection error
pj_error = [];

% Initiate log file
fid_log = fopen([output_fn '.log'],'w');
fprintf(fid_log,'Absoprtion reconstruction from amplitude only\n');
fprintf(fid_log,'Forward Mesh   = %s\n',fwd_fn);
if ischar(recon_basis)
    fprintf(fid_log,'Basis          = %s\n',recon_basis);
else
    fprintf(fid_log,'Basis          = %s\n',num2str(recon_basis));
end
fprintf(fid_log,'Frequency      = %f MHz\n',frequency);
fprintf(fid_log,'Data File      = %s\n',data_fn);
fprintf(fid_log,'Initial Reg    = %d\n',lambda);
fprintf(fid_log,'Filter         = %d\n',filter_n);
fprintf(fid_log,'Output Files   = %s_mua.sol\n',output_fn);
fprintf(fid_log,'               = %s_mus.sol\n',output_fn);


for it = 1 : iteration
    
    % Calculate jacobian
    [J,data]=jacobian_stnd(fwd_mesh,frequency);
    
    % Read reference data
    clear ref;
    ref(:,1) = log(data.amplitude);
    % $$$   ref(:,2) = data.phase;
    % $$$   ref(:,2) = ref(:,2)/180.0*pi;
    % $$$   ref(find(ref(:,2)<0),2) = ref(find(ref(:,2)<0),2) + (2*pi);
    % $$$   ref(find(ref(:,2)>(2*pi)),2) = ref(find(ref(:,2)>(2*pi)),2) - (2*pi);
    % $$$   ref = reshape(ref',length(ref)*2,1);
    
    data_diff = (anom-ref);
    
    pj_error = [pj_error sum((anom-ref).^2)];
    
    disp('---------------------------------');
    disp(['Iteration Number          = ' num2str(it)]);
    disp(['Projection error          = ' num2str(pj_error(end))]);
    
    fprintf(fid_log,'---------------------------------\n');
    fprintf(fid_log,'Iteration Number          = %d\n',it);
    fprintf(fid_log,'Projection error          = %f\n',pj_error(end));
    
    if it ~= 1
        p = (pj_error(end-1)-pj_error(end))*100/pj_error(end-1);
        disp(['Projection error change   = ' num2str(p) '%']);
        fprintf(fid_log,'Projection error change   = %f %%\n',p);
        if (p) <= 2
            disp('---------------------------------');
            disp('STOPPING CRITERIA REACHED');
            fprintf(fid_log,'---------------------------------\n');
            fprintf(fid_log,'STOPPING CRITERIA REACHED\n');
            break
        end
    end
    J = J.complete;
    % This calculates the mapping matrix that reduces Jacobian from nodal
    % values to regional value
    
    %   % Normalize Jacobian wrt optical values
    J = J*diag([fwd_mesh.mua]);
    
    l_step =51;
    [U,V,B] = lsqr_b_hybrid(J,data_diff,l_step,1);
    if it==1
        lambda = 1000;
    end
    l1 = 1000;
    for l_step =2:50
        T = eye(l_step);
        lambda = fminbnd(@(lambda) opt_lambda_cw(B(1:l_step,1:l_step+1), data_diff, lambda, V, J, T, U), 0, lambda, optimset( 'MaxIter', 1000, 'TolX', 1e-16));
        Hess = B(1:l_step,1:l_step+1)'*B(1:l_step,1:l_step+1);
        reg = lambda;
        yk = (Hess + reg.*eye(size(B(1:l_step,1:l_step+1),2)))\(norm(data_diff,2).*B(1:l_step,1:l_step+1)'*T(:,1));
        foo = V(:,1:length(yk))*yk;
        l1 = lambda;
        l12(l_step-1) = lambda;
        foo1 = foo.*[fwd_mesh.mua];
        mesh = fwd_mesh;
        mesh.mua = fwd_mesh.mua + foo1;
        mesh.kappa = 1./(3.*(fwd_mesh.mua + fwd_mesh.mus));
        [data]=femdata(mesh,frequency,mesh);
        
        % Read reference data
        clear ref1;
        ref1(:,1) = log(data.amplitude);
        data_diff1 = (anom-ref1);
        x_res(l_step-1) = norm(data_diff1);
    end
    in = find(x_res(:)==min(x_res))
    reg = l12(in);
    lambda = reg;
    reg
    Hess = B(1:l_step,1:l_step+1)'*B(1:l_step,1:l_step+1);
    yk = (Hess + reg.*eye(size(B(1:l_step,1:l_step+1),2)))\(norm(data_diff,2).*B(1:l_step,1:l_step+1)'*T(:,1));
    foo = V(:,1:length(yk))*yk;
    
    foo1 = foo.*[fwd_mesh.mua];
    % Update values
    %recon_mesh.kappa = recon_mesh.kappa + (foo(1:end/2));
    fwd_mesh.mua = fwd_mesh.mua + foo1;
    fwd_mesh.kappa = 1./(3.*(fwd_mesh.mua + fwd_mesh.mus));
    %fwd_mesh.mua = fwd_mesh.mua + foo;
    %recon_mesh.mus = (1./(3.*recon_mesh.kappa))-recon_mesh.mua;
    
    clear foo Hess Hess_norm tmp data_diff G
    
    % Interpolate optical properties to fine mesh
    %   [fwd_mesh,recon_mesh] = interpolatep2f(fwd_mesh,recon_mesh);
    
    % We dont like -ve mua or mus! so if this happens, terminate
    if (any(fwd_mesh.mua<0) | any(fwd_mesh.mus<0))
        disp('---------------------------------');
        disp('-ve mua or mus calculated...not saving solution');
        fprintf(fid_log,'---------------------------------\n');
        fprintf(fid_log,'STOPPING CRITERIA REACHED\n');
        break
    end
    
    % Filtering if needed!
    if filter_n > 1
        fwd_mesh = mean_filter(fwd_mesh,abs(filter_n));
    elseif filter_n < 1
        fwd_mesh = median_filter(fwd_mesh,abs(filter_n));
    end
    
    if it == 1
        fid = fopen([output_fn '_mua.sol'],'w');
    else
        fid = fopen([output_fn '_mua.sol'],'a');
    end
    fprintf(fid,'solution %g ',it);
    fprintf(fid,'-size=%g ',length(fwd_mesh.nodes));
    fprintf(fid,'-components=1 ');
    fprintf(fid,'-type=nodal\n');
    fprintf(fid,'%f ',fwd_mesh.mua);
    fprintf(fid,'\n');
    fclose(fid);
    
    if it == 1
        fid = fopen([output_fn '_mus.sol'],'w');
    else
        fid = fopen([output_fn '_mus.sol'],'a');
    end
    fprintf(fid,'solution %g ',it);
    fprintf(fid,'-size=%g ',length(fwd_mesh.nodes));
    fprintf(fid,'-components=1 ');
    fprintf(fid,'-type=nodal\n');
    fprintf(fid,'%f ',fwd_mesh.mus);
    fprintf(fid,'\n');
    fclose(fid);
end

% close log file!
time = toc;
fprintf(fid_log,'Computation TimeRegularization = %f\n',time);
fclose(fid_log);





function [val_int,recon_mesh] = interpolatef2r(fwd_mesh,recon_mesh,val)

% This function interpolates fwd_mesh into recon_mesh
% For the Jacobian it is an integration!
% modified to account for mua only
% h dehghani 22 March 2005
NNC = size(recon_mesh.nodes,1);
NNF = size(fwd_mesh.nodes,1);
NROW = size(val,1);
val_int = zeros(NROW,NNC);

for i = 1 : NNF
    if recon_mesh.coarse2fine(i,1) ~= 0
        val_int(:,recon_mesh.elements(recon_mesh.coarse2fine(i,1),:)) = ...
            val_int(:,recon_mesh.elements(recon_mesh.coarse2fine(i,1),:)) + ...
            val(:,i)*recon_mesh.coarse2fine(i,2:end);
        %val_int(:,recon_mesh.elements(recon_mesh.coarse2fine(i,1),:)+NNC) = ...
        %val_int(:,recon_mesh.elements(recon_mesh.coarse2fine(i,1),:)+NNC) + ...
        %	val(:,i+NNF)*recon_mesh.coarse2fine(i,2:end);
    elseif recon_mesh.coarse2fine(i,1) == 0
        dist = distance(fwd_mesh.nodes,fwd_mesh.bndvtx,recon_mesh.nodes(i,:));
        mindist = find(dist==min(dist));
        mindist = mindist(1);
        val_int(:,i) = val(:,mindist);
        %val_int(:,i+NNC) = val(:,mindist+NNF);
    end
end

for i = 1 : NNC
    if fwd_mesh.fine2coarse(i,1) ~= 0
        recon_mesh.mua(i,1) = (fwd_mesh.fine2coarse(i,2:end) * ...
            fwd_mesh.mua(fwd_mesh.elements(fwd_mesh.fine2coarse(i,1),:)));
        recon_mesh.mus(i,1) = (fwd_mesh.fine2coarse(i,2:end) * ...
            fwd_mesh.mus(fwd_mesh.elements(fwd_mesh.fine2coarse(i,1),:)));
        recon_mesh.kappa(i,1) = (fwd_mesh.fine2coarse(i,2:end) * ...
            fwd_mesh.kappa(fwd_mesh.elements(fwd_mesh.fine2coarse(i,1),:)));
        recon_mesh.region(i,1) = ...
            median(fwd_mesh.region(fwd_mesh.elements(fwd_mesh.fine2coarse(i,1),:)));
    elseif fwd_mesh.fine2coarse(i,1) == 0
        dist = distance(fwd_mesh.nodes,...
            fwd_mesh.bndvtx,...
            [recon_mesh.nodes(i,1:2) 0]);
        mindist = find(dist==min(dist));
        mindist = mindist(1);
        recon_mesh.mua(i,1) = fwd_mesh.mua(mindist);
        recon_mesh.mus(i,1) = fwd_mesh.mus(mindist);
        recon_mesh.kappa(i,1) = fwd_mesh.kappa(mindist);
        recon_mesh.region(i,1) = fwd_mesh.region(mindist);
    end
end

function [fwd_mesh,recon_mesh] = interpolatep2f(fwd_mesh,recon_mesh)


for i = 1 : length(fwd_mesh.nodes)
    fwd_mesh.mua(i,1) = ...
        (recon_mesh.coarse2fine(i,2:end) * ...
        recon_mesh.mua(recon_mesh.elements(recon_mesh.coarse2fine(i,1),:)));
    fwd_mesh.kappa(i,1) = ...
        (recon_mesh.coarse2fine(i,2:end) * ...
        recon_mesh.kappa(recon_mesh.elements(recon_mesh.coarse2fine(i,1),:)));
    fwd_mesh.mus(i,1) = ...
        (recon_mesh.coarse2fine(i,2:end) * ...
        recon_mesh.mus(recon_mesh.elements(recon_mesh.coarse2fine(i,1),:)));
end


