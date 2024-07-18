%
% Copyright (c) The acados authors.
%
% This file is part of acados.
%
% The 2-Clause BSD License
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
%
% 1. Redistributions of source code must retain the above copyright notice,
% this list of conditions and the following disclaimer.
%
% 2. Redistributions in binary form must reproduce the above copyright notice,
% this list of conditions and the following disclaimer in the documentation
% and/or other materials provided with the distribution.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.;

%


function generate_c_code_nonlinear_constr( model, opts, target_dir )

import casadi.*

casadi_opts = struct('mex', false, 'casadi_int', 'int', 'casadi_real', 'double');
check_casadi_version();

%% load model
x = model.sym_x;
u = model.sym_u;
p = model.sym_p;
z = model.sym_z;

if isa(x(1), 'casadi.SX')
    isSX = true;
else
    isSX = false;
end

model_name = model.name;

% cd to target folder
return_dir = pwd;
chdir(target_dir)

if isfield(model, 'constr_expr_h')
    h = model.constr_expr_h;
    % multipliers for hessian
    nh = length(h);
    if isSX
        lam_h = SX.sym('lam_h', nh, 1);
    else
        lam_h = MX.sym('lam_h', nh, 1);
    end
    % generate jacobians
    jac_ux = jacobian(h, [u; x]);
    jac_z  = jacobian(h, z);
    % generate hessian
    ux = [u; x];
    adj_ux = jtimes(h, ux, lam_h, true);
    % see https://github.com/casadi/casadi/issues/3703
    hess_ux = jacobian(adj_ux, ux, struct('symmetric', isSX));

    adj_z = jtimes(h, z, lam_h, true);
    hess_z = jacobian(adj_z, z, struct('symmetric', isSX));

    % Set up functions
    h_fun = Function([model_name,'_constr_h_fun'], {x, u, z, p}, {h});
    h_fun_jac_uxt_zt = Function([model_name,'_constr_h_fun_jac_uxt_zt'], {x, u, z, p}, {h, jac_ux', jac_z'});
    h_fun_jac_uxt_zt_hess = Function([model_name,'_constr_h_fun_jac_uxt_zt_hess'],...
                                 {x, u, lam_h, z, p}, {h, jac_ux', hess_ux, jac_z', hess_z});
    % generate C code
    h_fun.generate([model_name,'_constr_h_fun'], casadi_opts);
    h_fun_jac_uxt_zt.generate([model_name,'_constr_h_fun_jac_uxt_zt'], casadi_opts);
    h_fun_jac_uxt_zt_hess.generate([model_name,'_constr_h_fun_jac_uxt_zt_hess'], casadi_opts);
end

if isfield(model, 'constr_expr_h_0')
    h_0 = model.constr_expr_h_0;
    % multipliers for hessian
    nh_0 = length(h_0);
    if isSX
        lam_h_0 = SX.sym('lam_h', nh_0, 1);
    else
        lam_h_0 = MX.sym('lam_h', nh_0, 1);
    end
    % generate jacobians
    jac_ux_0 = jacobian(h_0, [u; x]);
    jac_z_0  = jacobian(h_0, z);

    % generate hessian
    adj_ux_0 = jtimes(h_0, [u; x], lam_h_0, true);
    hess_ux_0 = jacobian(adj_ux_0, [u; x], struct('symmetric', isSX));

    adj_z_0 = jtimes(h_0, z, lam_h_0, true);
    hess_z_0 = jacobian(adj_z_0, z, struct('symmetric', isSX));

    % Set up functions
    h_0_fun = Function([model_name,'_constr_h_0_fun'], {x, u, z, p}, {h_0});
    h_0_fun_jac_uxt_zt = Function([model_name,'_constr_h_0_fun_jac_uxt_zt'], {x, u, z, p}, {h_0, jac_ux_0', jac_z_0'});
    h_0_fun_jac_uxt_zt_hess = Function([model_name,'_constr_h_0_fun_jac_uxt_zt_hess'], {x, u, lam_h_0, z, p}, {h_0, jac_ux_0', hess_ux_0, jac_z_0', hess_z_0});
    % generate C code
    h_0_fun.generate([model_name,'_constr_h_0_fun'], casadi_opts);
    h_0_fun_jac_uxt_zt.generate([model_name,'_constr_h_0_fun_jac_uxt_zt'], casadi_opts);
    h_0_fun_jac_uxt_zt_hess.generate([model_name,'_constr_h_0_fun_jac_uxt_zt_hess'], casadi_opts);
end

if isfield(model, 'constr_expr_h_e')
    % NOTE: terminal node has no u, z
    h_e = model.constr_expr_h_e;
    % multipliers for hessian
    nh_e = length(h_e);
    if isSX
        lam_h_e = SX.sym('lam_h', nh_e, 1);
    else
        lam_h_e = MX.sym('lam_h', nh_e, 1);
    end
    % generate jacobians
    jac_x_e = jacobian(h_e, x);
    % generate adjoint
    adj_ux_e = jtimes(h_e, x, lam_h_e, true);
    % generate hessian
    hess_ux_e = jacobian(adj_ux_e, x, struct('symmetric', isSX));
    % Set up functions
    h_e_fun = Function([model_name,'_constr_h_e_fun'], {x, p}, {h_e});
    h_e_fun_jac_uxt_zt = Function([model_name,'_constr_h_e_fun_jac_uxt_zt'], {x, p}, {h_e, jac_x_e'});
    h_e_fun_jac_uxt_zt_hess = Function([model_name,'_constr_h_e_fun_jac_uxt_zt_hess'], {x, lam_h_e, p}, {h_e, jac_x_e', hess_ux_e});
    % generate C code
    h_e_fun.generate([model_name,'_constr_h_e_fun'], casadi_opts);
    h_e_fun_jac_uxt_zt.generate([model_name,'_constr_h_e_fun_jac_uxt_zt'], casadi_opts);
    h_e_fun_jac_uxt_zt_hess.generate([model_name,'_constr_h_e_fun_jac_uxt_zt_hess'], casadi_opts);
end

chdir(return_dir)

end
