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

classdef AcadosOcp < handle
    properties
        dims
        cost
        constraints
        solver_options
        model
        parameter_values % initial value of the parameter
        acados_include_path
        acados_lib_path
        problem_class
        simulink_opts
        cython_include_dirs
        code_export_directory
        json_file
        shared_lib_ext
        name
    end
    methods
        function obj = AcadosOcp()
            obj.dims = AcadosOcpDims();
            obj.cost = AcadosOcpCost();
            obj.constraints = AcadosOcpConstraints();
            obj.solver_options = AcadosOcpOptions();
            obj.model = AcadosModel();

            obj.parameter_values = [];
            obj.problem_class = 'OCP';
            obj.simulink_opts = [];
            obj.cython_include_dirs = [];
            obj.json_file = 'acados_ocp_nlp.json';
            obj.shared_lib_ext = '.so';
            obj.name = 'ocp';
            if ismac()
                obj.shared_lib_ext = '.dylib';
            end
            obj.code_export_directory = 'c_generated_code';

            % set include and lib path
            acados_folder = getenv('ACADOS_INSTALL_DIR');
            obj.acados_include_path = [acados_folder, '/include'];
            obj.acados_lib_path = [acados_folder, '/lib'];
        end

        function s = struct(self)
            if exist('properties')
                publicProperties = eval('properties(self)');
            else
                publicProperties = fieldnames(self);
            end
            s = struct();
            for fi = 1:numel(publicProperties)
                s.(publicProperties{fi}) = self.(publicProperties{fi});
            end
        end

        function make_consistent(self)
            self.model.make_consistent(self.dims);

            N = self.dims.N;

            model = self.model;
            dims = self.dims;
            cost = self.cost;
            constraints = self.constraints;
            opts = self.solver_options;

            self.detect_cost_and_constraints();

            % detect GNSF structure
            if strcmp(opts.integrator_type, 'GNSF')
                if dims.gnsf_nx1 + dims.gnsf_nx2 ~= dims.nx
                    % TODO: properly interface those.
                    gnsf_transcription_opts = struct();
                    detect_gnsf_structure(model, dims, gnsf_transcription_opts);
                else
                    warning('No GNSF model detected, assuming all required fields are set.')
                end
            end

            % OCP name
            self.name = model.name;

            % parameters
            if isempty(self.parameter_values)
                if dims.np > 0
                    warning(['self.parameter_values are not set.', ...
                            10 'Using zeros(np,1) by default.' 10 'You can update them later using set().']);
                end
                self.parameter_values = zeros(self.dims.np,1);
            elseif length(self.parameter_values) ~= self.dims.np
                error(['parameters_values has the wrong shape. Expected: ' num2str(self.dims.np)])
            end

            %% cost
            % initial
            if strcmp(cost.cost_type_0, 'LINEAR_LS')
                if ~isempty(cost.W_0) && ~isempty(cost.Vx_0) && ~isempty(cost.Vu_0)
                    ny = length(cost.W_0);

                    if isempty(cost.yref_0)
                        warning(['yref_0 not defined provided.' 10 'Using zeros(ny_0,1) by default.']);
                        self.cost.yref_0 = zeros(ny,1);
                    end
                    if ny ~= size(cost.Vx_0, 1) || ny ~= size(cost.Vu_0, 1) || ny ~= size(cost.yref_0, 1)
                        error('inconsistent dimension ny, regarding W_0, Vx_0, Vu_0, yref_0.');
                    end
                else
                    error('setting linear least square cost: need W_0, Vx_0, Vu_0, at least one missing.')
                end
                dims.ny_0 = ny;
            elseif strcmp(cost.cost_type_0, 'NONLINEAR_LS')
                if ~isempty(cost.W_0) && ~isempty(model.cost_y_expr_0)
                    ny = length(cost.W_0);
                    if isempty(cost.yref_0)
                        warning(['yref_0 not defined provided.' 10 'Using zeros(ny_0,1) by default.']);
                        self.cost.yref_0 = zeros(ny,1);
                    end
                    if ny ~= length(model.cost_y_expr_0) || ny ~= size(cost.yref_0, 1)
                        error('inconsistent dimension ny_0, regarding W_0, cost_y_expr_0, yref_0.');
                    end
                else
                    error('setting nonlinear least square cost: need W_0, cost_y_expr_0, at least one missing.')
                end
                dims.ny_0 = ny;
            end

            % path
            if strcmp(cost.cost_type, 'LINEAR_LS')
                if ~isempty(cost.W) && ~isempty(cost.Vx) && ~isempty(cost.Vu)
                    ny = length(cost.W);
                    if isempty(cost.yref)
                        warning(['yref not defined provided.' 10 'Using zeros(ny,1) by default.']);
                        self.cost.yref = zeros(ny,1);
                    end
                    if ny ~= size(cost.Vx, 1) || ny ~= size(cost.Vu, 1) || ny ~= size(cost.yref, 1)
                        error('inconsistent dimension ny, regarding W, Vx, Vu, yref.');
                    end
                else
                    error('setting linear least square cost: need W, Vx, Vu, at least one missing.')
                end
                dims.ny = ny;
            elseif strcmp(cost.cost_type, 'NONLINEAR_LS')
                if ~isempty(cost.W) && ~isempty(model.cost_y_expr)
                    ny = length(cost.W);
                    if isempty(cost.yref)
                        warning(['yref not defined provided.' 10 'Using zeros(ny,1) by default.']);
                        self.cost.yref = zeros(ny,1);
                    end
                    if ny ~= length(model.cost_y_expr) || ny ~= size(cost.yref, 1)
                        error('inconsistent dimension ny, regarding W, cost_y_expr, yref.');
                    end
                else
                    error('setting nonlinear least square cost: need W, cost_y_expr, at least one missing.')
                end
                dims.ny = ny;
            end

            % terminal
            if strcmp(cost.cost_type_e, 'LINEAR_LS')
                if ~isempty(cost.W_e) && ~isempty(cost.Vx_e)
                    ny_e = length(cost.W_e);
                    if isempty(cost.yref_e)
                        warning(['yref_e not defined provided.' 10 'Using zeros(ny_e,1) by default.']);
                        self.cost.yref_e = zeros(ny_e,1);
                    end
                    if ny_e ~= size(cost.Vx_e, 1) || ny_e ~= size(cost.yref_e, 1)
                        error('inconsistent dimension ny_e, regarding W_e, Vx_e, yref_e');
                    end
                elseif ~~isempty(cost.W_e) && ~~isempty(cost.Vx_e)
                    ny_e = 0;
                    warning('Fields W_e and Vx_e not provided. Using empty ls terminal cost.')
                else
                    error('setting linear least square cost: need W_e, Vx_e, at least one missing.')
                end
                dims.ny_e = ny_e;
            elseif strcmp(cost.cost_type_e, 'NONLINEAR_LS')
                if ~isempty(cost.W_e) && ~isempty(model.cost_y_expr_e)
                    ny_e = length(cost.W_e);
                    if isempty(cost.yref_e)
                        warning(['yref_e not defined provided.' 10 'Using zeros(ny_e,1) by default.']);
                        self.cost.yref_e = zeros(ny_e,1);
                    end
                    if ny_e ~= length(model.cost_y_expr_e) || ny_e ~= size(cost.yref_e, 1)
                        error('inconsistent dimension ny_e, regarding W_e, cost_y_expr_e, yref_e.');
                    end
                else
                    error('setting nonlinear least square cost: need W_e, cost_y_expr_e, at least one missing.')
                end
                dims.ny_e = ny_e;
            end

            % cost integration
            if strcmp(opts.cost_discretization, "INTEGRATOR")
                if ~(strcmp(cost.cost_type, "NONLINEAR_LS") || strcmp(cost.cost_type, "CONVEX_OVER_NONLINEAR"))
                    error('INTEGRATOR cost discretization requires CONVEX_OVER_NONLINEAR or NONLINEAR_LS cost type for path cost.')
                end
                if ~(strcmp(cost.cost_type_0, "NONLINEAR_LS") || strcmp(cost.cost_type_0, "CONVEX_OVER_NONLINEAR"))
                    error('INTEGRATOR cost discretization requires CONVEX_OVER_NONLINEAR or NONLINEAR_LS cost type for initial cost.')
                end
            end


            %% constraints
            % initial
            if ~isempty(constraints.idxbx_0) && ~isempty(constraints.lbx_0) && ~isempty(constraints.ubx_0)
                nbx_0 = length(constraints.lbx_0);
                if nbx_0 ~= length(constraints.ubx_0) || nbx_0 ~= length(constraints.idxbx_0)
                    error('inconsistent dimension nbx_0, regarding Jbx_0, lbx_0, ubx_0.');
                end
            elseif ~isempty(constraints.idxbx_0) || ~isempty(constraints.lbx_0) || ~isempty(constraints.ubx_0)
                error('setting bounds on x: need Jbx_0, lbx_0, ubx_0, at least one missing.');
            else
                % no initial state constraint
                disp("OCP without constraints on initial state detected.")
                nbx_0 = 0;
            end
            dims.nbx_0 = nbx_0;

            if ~isempty(constraints.idxbxe_0)
                dims.nbxe_0 = length(constraints.idxbxe_0);
            else
                % no equalities on initial state.
                constraints.idxbxe_0 = [];
                dims.nbxe_0 = 0;
            end

            % path
            if ~isempty(constraints.idxbx) && ~isempty(constraints.lbx) && ~isempty(constraints.ubx)
                nbx = length(constraints.lbx);
                if nbx ~= length(constraints.ubx) || nbx ~= length(constraints.idxbx)
                    error('inconsistent dimension nbx, regarding Jbx, lbx, ubx.');
                end
            elseif ~isempty(constraints.idxbx) || ~isempty(constraints.lbx) || ~isempty(constraints.ubx)
                error('setting bounds on x: need Jbx, lbx, ubx, at least one missing.');
            else
                nbx = 0;
            end
            dims.nbx = nbx;

            if ~isempty(constraints.idxbu) && ~isempty(constraints.lbu) && ~isempty(constraints.ubu)
                nbu = length(constraints.lbu);
                if nbu ~= length(constraints.ubu) || nbu ~= length(constraints.idxbu)
                    error('inconsistent dimension nbu, regarding Jbu, lbu, ubu.');
                end
            elseif ~isempty(constraints.idxbu) || ~isempty(constraints.lbu) || ~isempty(constraints.ubu)
                error('setting bounds on u: need Jbu, lbu, ubu, at least one missing.');
            else
                nbu = 0;
            end
            dims.nbu = nbu;

            if ~isempty(constraints.C) && ~isempty(constraints.D) && ...
               ~isempty(constraints.lg) && ~isempty(constraints.ug)
                ng = length(constraints.lg);
                if ng ~= length(constraints.ug) || ng ~= size(constraints.C, 1) || ng ~= size(constraints.D, 1)
                    error('inconsistent dimension ng, regarding C, D, lg, ug.');
                end
            elseif ~isempty(constraints.C) || ~isempty(constraints.D) || ...
                   ~isempty(constraints.lg) || ~isempty(constraints.ug)
                error('setting general linear constraints: need C, D, lg, ug, at least one missing.');
            else
                ng = 0;
            end
            dims.ng = ng;

            if ~isempty(model.con_h_expr) && ...
                     ~isempty(constraints.lh) && ~isempty(constraints.uh)
                nh = length(constraints.lh);
                if nh ~= length(constraints.uh) || nh ~= length(model.con_h_expr)
                    error('inconsistent dimension nh, regarding expr_h, lh, uh.');
                end
            elseif ~isempty(model.con_h_expr) || ...
                   ~isempty(constraints.lh) || ~isempty(constraints.uh)
                error('setting external constraint function h: need expr_h, lh, uh at least one missing.');
            else
                nh = 0;
            end
            dims.nh = nh;

            if ~isempty(model.con_h_expr_0) && ...
                    ~isempty(constraints.lh_0) && ~isempty(constraints.uh_0)
            nh_0 = length(constraints.lh_0);
            if nh_0 ~= length(constraints.uh_0) || nh_0 ~= length(model.con_h_expr_0)
                error('inconsistent dimension nh_0, regarding expr_h_0, lh_0, uh_0.');
            end
            elseif ~isempty(model.con_h_expr_0) || ...
                ~isempty(constraints.lh_0) || ~isempty(constraints.uh_0)
            error('setting external constraint function h: need expr_h_0, lh_0, uh_0 at least one missing.');
            else
                nh_0 = 0;
            end
            dims.nh_0 = nh_0;

            % terminal
            if ~isempty(constraints.idxbx_e) && ~isempty(constraints.lbx_e) && ~isempty(constraints.ubx_e)
                nbx_e = length(constraints.lbx_e);
                if nbx_e ~= length(constraints.ubx_e) || nbx_e ~= length(constraints.idxbx_e)
                    error('inconsistent dimension nbx_e, regarding Jbx_e, lbx_e, ubx_e.');
                end
            elseif ~isempty(constraints.idxbx_e) || ~isempty(constraints.lbx_e) || ~isempty(constraints.ubx_e)
                error('setting bounds on x: need Jbx_e, lbx_e, ubx_e, at least one missing.');
            else
                nbx_e = 0;
            end
            dims.nbx_e = nbx_e;

            if ~isempty(constraints.C_e) && ...
               ~isempty(constraints.lg_e) && ~isempty(constraints.ug_e)
                ng_e = length(constraints.lg_e);
                if ng_e ~= length(constraints.ug_e) || ng_e ~= size(constraints.C_e, 1)
                    error('inconsistent dimension ng_e, regarding C_e, lg_e, ug_e.');
                end
            elseif ~isempty(constraints.C_e) || ...
                   ~isempty(constraints.lg_e) || ~isempty(constraints.ug_e)
                error('setting general linear constraints: need C_e, lg_e, ug_e, at least one missing.');
            else
                ng_e = 0;
            end
            dims.ng_e = ng_e;

            if ~isempty(model.con_h_expr_e) && ...
                     ~isempty(constraints.lh_e) && ~isempty(constraints.uh_e)
                nh_e = length(constraints.lh_e);
                if nh_e ~= length(constraints.uh_e) || nh_e ~= length(model.con_h_expr_e)
                    error('inconsistent dimension nh_e, regarding expr_h_e, lh_e, uh_e.');
                end
            elseif ~isempty(model.con_h_expr_e) || ...
                   ~isempty(constraints.lh_e) || ~isempty(constraints.uh_e)
                error('setting external constraint function h: need expr_h_e, lh_e, uh_e at least one missing.');
            else
                nh_e = 0;
            end
            dims.nh_e = nh_e;

            %% slack dimensions
            if ~isempty(constraints.idxsbx)
                nsbx = length(constraints.idxsbx);
            else
                nsbx = 0;
            end

            if ~isempty(constraints.idxsbu)
                nsbu = length(constraints.idxsbu);
            else
                nsbu = 0;
            end

            if ~isempty(constraints.idxsg)
                nsg = length(constraints.idxsg);
            else
                nsg = 0;
            end
            if ~isempty(constraints.idxsh)
                nsh = length(constraints.idxsh);
            else
                nsh = 0;
            end
            if ~isempty(constraints.idxsphi)
                nsphi = length(constraints.idxsphi);
            else
                nsphi = 0;
            end

            ns = nsbx + nsbu + nsg + nsh + nsphi;
            wrong_field = '';
            if ~isempty(cost.Zl) && ~all(size(cost.Zl) == [ns, 1])
                wrong_field = 'Zl';
                dim = size(cost.Zl);
            elseif ~isempty(cost.Zu) && ~all(size(cost.Zu) == [ns, 1])
                wrong_field = 'Zu';
                dim = size(cost.Zu);
            elseif ~isempty(cost.zl) && ~all(size(cost.zl) == [ns, 1])
                wrong_field = 'zl';
                dim = size(cost.zl);
            elseif ~isempty(cost.zu) && ~all(size(cost.zu) == [ns, 1])
                wrong_field = 'zu';
                dim = size(cost.zu);
            end

            if ~strcmp(wrong_field, '')
                error(['Inconsistent size for field ', wrong_field, ' with dimension ', num2str(dim),...
                      '. Detected ns = ', num2str(ns), ' = nsbx + nsbu + nsg + nsh + nsphi.',...
                      ' With nsbx = ', num2str(nsbx), ', nsbu = ', num2str(nsbu), ' nsg = ', num2str(nsg),...
                      ' nsh = ', num2str(nsh), ', nsphi = ', num2str(nsphi), '.'])
            end

            constraints.lsbu = zeros(nsbu, 1);
            constraints.usbu = zeros(nsbu, 1);
            constraints.lsbx = zeros(nsbx, 1);
            constraints.usbx = zeros(nsbx, 1);
            constraints.lsh = zeros(nsh, 1);
            constraints.ush = zeros(nsh, 1);
            constraints.lsphi = zeros(nsphi, 1);
            constraints.usphi = zeros(nsphi, 1);

            dims.ns = ns;
            dims.nsbx = nsbx;
            dims.nsbu = nsbu;
            dims.nsg = nsg;
            dims.nsh = nsh;
            dims.nsphi = nsphi;

            % slacks at initial stage
            if ~isempty(constraints.idxsh_0)
                nsh_0 = length(constraints.idxsh_0);
            else
                nsh_0 = 0;
            end
            if ~isempty(constraints.idxsphi_0)
                nsphi_0 = length(constraints.idxsphi_0);
            else
                nsphi_0 = 0;
            end

            ns_0 = nsbu + nsg + nsh_0 + nsphi_0;
            wrong_field = '';
            if ~isempty(cost.Zl_0) && ~all(size(cost.Zl_0) == [ns_0, 1])
                wrong_field = 'Zl_0';
                dim = size(cost.Zl_0);
            elseif ~isempty(cost.Zu_0) && ~all(size(cost.Zu_0) == [ns_0, 1])
                wrong_field = 'Zu_0';
                dim = size(cost.Zu_0);
            elseif ~isempty(cost.zl_0) && ~all(size(cost.zl_0) == [ns_0, 1])
                wrong_field = 'zl_0';
                dim = size(cost.zl_0);
            elseif ~isempty(cost.zu_0) && ~all(size(cost.zu_0) == [ns_0, 1])
                wrong_field = 'zu_0';
                dim = size(cost.zu_0);
            end

            if ~strcmp(wrong_field, '')
                error(['Inconsistent size for field', wrong_field, ' with dimension ', num2str(dim),...
                        '. Detected ns_0 = ', num2str(ns_0), ' = nsbu + nsg + nsh_0 + nsphi_0.',...
                        ' With nsg = ', num2str(nsg), ' nsh_0 = ', num2str(nsh_0), ', nsphi_0 = ', num2str(nsphi_0), '.'])
            end

            constraints.lsh_0 = zeros(nsh_0, 1);
            constraints.ush_0 = zeros(nsh_0, 1);
            constraints.lsphi_0 = zeros(nsphi_0, 1);
            constraints.usphi_0 = zeros(nsphi_0, 1);

            dims.ns_0 = ns_0;
            dims.nsh_0 = nsh_0;
            dims.nsphi_0 = nsphi_0;

            %% terminal slack dimensions
            if ~isempty(constraints.idxsbx_e)
                nsbx_e = length(constraints.idxsbx_e);
            else
                nsbx_e = 0;
            end

            if ~isempty(constraints.idxsg_e)
                nsg_e = length(constraints.idxsg_e);
            else
                nsg_e = 0;
            end
            if ~isempty(constraints.idxsh_e)
                nsh_e = length(constraints.idxsh_e);
            else
                nsh_e = 0;
            end
            if ~isempty(constraints.idxsphi_e)
                nsphi_e = length(constraints.idxsphi_e);
            else
                nsphi_e = 0;
            end

            ns_e = nsbx_e + nsg_e + nsh_e + nsphi_e;
            wrong_field = '';
            if ~isempty(cost.Zl_e) && ~all(size(cost.Zl_e) == [ns_e, 1])
                wrong_field = 'Zl_e';
                dim = size(cost.Zl_e);
            elseif ~isempty(cost.Zu_e) && ~all(size(cost.Zu_e) == [ns_e, 1])
                wrong_field = 'Zu_e';
                dim = size(cost.Zu_e);
            elseif ~isempty(cost.zl_e) && ~all(size(cost.zl_e) == [ns_e, 1])
                wrong_field = 'zl_e';
                dim = size(cost.zl_e);
            elseif ~isempty(cost.zu_e) && ~all(size(cost.zu_e) == [ns_e, 1])
                wrong_field = 'zu_e';
                dim = size(cost.zu_e);
            end

            if ~strcmp(wrong_field, '')
                error(['Inconsistent size for field', wrong_field, ' with dimension ', num2str(dim),...
                        '. Detected ns_e = ', num2str(ns_e), ' = nsbx_e + nsg_e + nsh_e + nsphi_e.',...
                        ' With nsbx_e = ', num2str(nsbx_e), ' nsg_e = ', num2str(nsg_e),...
                        ' nsh_e = ', num2str(nsh_e), ', nsphi_e = ', num2str(nsphi_e), '.'])
            end


            constraints.lsbx_e = zeros(nsbx_e, 1);
            constraints.usbx_e = zeros(nsbx_e, 1);
            constraints.lsh_e = zeros(nsh_e, 1);
            constraints.ush_e = zeros(nsh_e, 1);
            constraints.lsphi_e = zeros(nsphi_e, 1);
            constraints.usphi_e = zeros(nsphi_e, 1);

            dims.ns_e = ns_e;
            dims.nsbx_e = nsbx_e;
            dims.nsg_e = nsg_e;
            dims.nsh_e = nsh_e;
            dims.nsphi_e = nsphi_e;

            % shooting nodes -> time_steps
            N = self.dims.N;
            if length(opts.tf) ~= 1 || opts.tf < 0
                error('time horizon tf should be a nonnegative number');
            end

            if ~isempty(opts.shooting_nodes)
                if N + 1 ~= length(opts.shooting_nodes)
                    error('inconsistent dimension N regarding shooting nodes.');
                end
                for i=1:N
                    opts.time_steps(i) = opts.shooting_nodes(i+1) - opts.shooting_nodes(i);
                end
                sum_time_steps = sum(opts.time_steps);
                if abs((sum_time_steps - opts.tf) / opts.tf) > 1e-14
                    warning('shooting nodes are not consistent with time horizon tf, rescaling automatically');
                    opts.time_steps = opts.time_steps * opts.tf / sum_time_steps;
                end
            elseif ~isempty(opts.time_steps)
                if N ~= length(opts.time_steps)
                    error('inconsistent dimension N regarding time steps.');
                end
                sum_time_steps = sum(opts.time_steps);
                if abs((sum_time_steps - opts.tf) / opts.tf) > 1e-14
                    error(['time steps are not consistent with time horizon tf, ', ...
                        'got tf = ' num2str(opts.tf) '; sum(time_steps) = ' num2str(sum_time_steps) '.']);
                end
            else
                opts.time_steps = opts.tf/N * ones(N,1);
            end
            % add consistent shooting_nodes e.g. for plotting;
            if isempty(opts.shooting_nodes)
                opts.shooting_nodes = zeros(N+1, 1);
                for i = 1:N
                    opts.shooting_nodes(i+1) = sum(opts.time_steps(1:i));
                end
            end
            if any(opts.time_steps < 0)
                error(['ocp discretization: time_steps between shooting nodes must all be > 0', ...
                    ' got: ' num2str(opts.time_steps)])
            end
            if ~isempty(opts.sim_method_num_stages)
                if(strcmp(opts.integrator_type, "ERK"))
                    if (any(opts.sim_method_num_stages < 1) || any(opts.sim_method_num_stages > 4))
                        error(['ERK: num_stages = ', num2str(opts.sim_method_num_stages) ' not available. Only number of stages = {1,2,3,4} implemented!']);
                    end
                end
            end

            % set integrator time automatically
            opts.Tsim = opts.time_steps(1);

            % qpdunes
            if ~isempty(strfind(opts.qp_solver,'qpdunes'))
                constraints.idxbxe_0 = [];
                dims.nbxe_0 = 0;
            end

            %% options sanity checks
            if length(opts.sim_method_num_steps) == 1
                opts.sim_method_num_steps = opts.sim_method_num_steps * ones(1, N);
            elseif length(opts.sim_method_num_steps) ~= N
                error('sim_method_num_steps must be a scalar or a vector of length N');
            end
            if length(opts.sim_method_num_stages) == 1
                opts.sim_method_num_stages = opts.sim_method_num_stages * ones(1, N);
            elseif length(opts.sim_method_num_stages) ~= N
                error('sim_method_num_stages must be a scalar or a vector of length N');
            end
            if length(opts.sim_method_jac_reuse) == 1
                opts.sim_method_jac_reuse = opts.sim_method_jac_reuse * ones(1, N);
            elseif length(opts.sim_method_jac_reuse) ~= N
                error('sim_method_jac_reuse must be a scalar or a vector of length N');
            end

            if strcmp(opts.nlp_solver_type, "PARTIAL_CONDENSING_HPMPC") || ...
                strcmp(opts.nlp_solver_type, "PARTIAL_CONDENSING_QPDUNES") || ...
                strcmp(opts.nlp_solver_type, "PARTIAL_CONDENSING_OOQP")
                if self.dims.ns > 0 || self.dims.ns_e > 0
                    error(['selected QP solver ', opts.nlp_solver_type, ' does not support soft constraints (yet).'])
                end
            end

            % fixed hessian
            if opts.fixed_hess
                if opts.hessian_approx == 'EXACT'
                    error('fixed_hess and hessian_approx = EXACT are incompatible')
                end
                if ~(strcmp(cost.cost_type_0, "LINEAR_LS") && strcmp(cost.cost_type, "LINEAR_LS") && strcmp(cost.cost_type_e, "LINEAR_LS"))
                    error('fixed_hess requires LINEAR_LS cost type')
                end
            end

            % TODO: add checks for solution sensitivities when brining them to Matlab

            % check if qp_solver_cond_N is set
            if isempty(opts.qp_solver_cond_N)
                opts.qp_solver_cond_N = N;
            end

            if ~isempty(opts.qp_solver_cond_block_size)
                if sum(opts.qp_solver_cond_block_size) ~= N
                    error(['sum(qp_solver_cond_block_size) =', num2str(sum(opts.qp_solver_cond_block_size)), ' != N = {dims.N}.']);
                end
                if length(opts.qp_solver_cond_block_size) ~= opts.qp_solver_cond_N+1
                    error('qp_solver_cond_block_size should have length qp_solver_cond_N+1.');
                end
            end

            if strcmp(opts.nlp_solver_type, "DDP")
                if ~strcmp(opts.qp_solver, "PARTIAL_CONDENSING_HPIPM") || (opts.qp_solver_cond_N ~= dims.N)
                    error('DDP solver only supported for PARTIAL_CONDENSING_HPIPM with qp_solver_cond_N == N.');
                end
                if any([dims.nbu, dims.nbx, dims.ng, dims.nh, dims.nphi])
                    error('DDP only supports initial state constraints, got path constraints.')
                end
                if any([dims.ng_e, dims.nphi_e, dims.nh_e])
                    error('DDP only supports initial state constraints, got terminal constraints.')
                end
            end

            % Set default parameters for globalization
            if isempty(opts.alpha_min)
                if strcmp(opts.globalization, 'FUNNEL_L1PEN_LINESEARCH')
                    opts.alpha_min = 1e-17;
                else
                    opts.alpha_min = 0.05;
                end
            end

            if isempty(opts.alpha_reduction)
                if strcmp(opts.globalization, 'FUNNEL_L1PEN_LINESEARCH')
                    opts.alpha_reduction = 0.5;
                else
                    opts.alpha_reduction = 0.7;
                end
            end

            if isempty(opts.eps_sufficient_descent)
                if strcmp(opts.globalization, 'FUNNEL_L1PEN_LINESEARCH')
                    opts.eps_sufficient_descent = 1e-6;
                else
                    opts.eps_sufficient_descent = 1e-4;
                end
            end

            if isempty(opts.eval_residual_at_max_iter)
                if strcmp(opts.globalization, 'FUNNEL_L1PEN_LINESEARCH')
                    opts.eval_residual_at_max_iter = true;
                else
                    opts.eval_residual_at_max_iter = false;
                end
            end

            if isempty(opts.full_step_dual)
                if strcmp(opts.globalization, 'FUNNEL_L1PEN_LINESEARCH')
                    opts.full_step_dual = 1;
                else
                    opts.full_step_dual = 0;
                end
            end

            % sanity check for Funnel globalization and SQP
            if strcmp(opts.globalization, 'FUNNEL_L1PEN_LINESEARCH') && ~strcmp(opts.nlp_solver_type, 'SQP')
                error('FUNNEL_L1PEN_LINESEARCH only supports SQP.');
            end

            % termination
            if isempty(opts.nlp_solver_tol_min_step_norm)
                if strcmp(opts.globalization, 'FUNNEL_L1PEN_LINESEARCH')
                    opts.nlp_solver_tol_min_step_norm = 1e-12;
                else
                    opts.nlp_solver_tol_min_step_norm = 0.0;
                end
            end
        end

        function [] = detect_cost_and_constraints(self)
            % detect cost type
            stage_types = {'initial', 'path', 'terminal'};
            cost_types = {self.cost.cost_type_0, self.cost.cost_type, self.cost.cost_type_e};

            for n=1:3
                if strcmp(cost_types{n}, 'AUTO')
                    detect_cost_type(self.model, self.cost, self.dims, stage_types{n});
                end
            end

            % if initial is empty, copy path cost
            % TODO: move this to make_consistent? should happen way before?
            if isempty(cost_types{1})
                warning("cost_type_0 not set, using path cost");
                self.cost.cost_type_0 = self.cost.cost_type;
                if (strcmp(self.cost.cost_type, 'LINEAR_LS'))
                    self.cost.Vx_0 = self.cost.Vx;
                    self.cost.Vu_0 = self.cost.Vu;
                    self.cost.Vz_0 = self.cost.Vz;
                elseif (strcmp(self.cost.cost_type, 'NONLINEAR_LS'))
                    self.model.cost_y_expr_0 = self.model.cost_y_expr;
                elseif (strcmp(self.cost.cost_type, 'EXTERNAL'))
                    self.cost.cost_ext_fun_type_0 = self.cost.cost_ext_fun_type;
                    if strcmp(self.cost.cost_ext_fun_type_0, 'casadi')
                        self.model.cost_expr_ext_cost_0 = self.model.cost_expr_ext_cost;
                        self.model.cost_expr_ext_cost_custom_hess_0 = self.model.cost_expr_ext_cost_custom_hess;
                    else % generic
                        self.cost.cost_source_ext_cost_0 = self.cost.cost_source_ext_cost;
                        self.cost.cost_function_ext_cost_0 = self.cost.cost_function_ext_cost;
                    end
                end
                if (strcmp(self.cost.cost_type, 'LINEAR_LS')) || (strcmp(self.cost.cost_type, 'NONLINEAR_LS'))
                    self.cost.W_0 = self.cost.W;
                    self.cost.yref_0 = self.cost.yref;
                    self.dims.ny_0 = self.dims.ny;
                end
            end

            % detect constraint structure
            constraint_types = {self.constraints.constr_type_0, self.constraints.constr_type, self.constraints.constr_type_e};
            for n=1:3
                if strcmp(constraint_types{n}, 'AUTO')
                    detect_constr(self.model, self.constraints, stage_types{n});
                end
            end
        end

        function generate_external_functions(ocp)

            %% generate C code for CasADi functions / copy external functions
            cost = ocp.cost;
            solver_opts = ocp.solver_options;
            constraints = ocp.constraints;
            dims = ocp.dims;

            % options for code generation
            code_gen_opts = struct();
            code_gen_opts.generate_hess = strcmp(solver_opts.hessian_approx, 'EXACT');
            code_gen_opts.with_solution_sens_wrt_params = solver_opts.with_solution_sens_wrt_params;
            code_gen_opts.with_value_sens_wrt_params = solver_opts.with_value_sens_wrt_params;

            % dynamics
            % model dir is always need, other dirs are  only created if necessary
            model_dir = fullfile(pwd, ocp.code_export_directory, [ocp.name '_model']);
            check_dir_and_create(model_dir);

            if (strcmp(solver_opts.integrator_type, 'ERK'))
                generate_c_code_explicit_ode(ocp.model, code_gen_opts, model_dir);
            elseif (strcmp(solver_opts.integrator_type, 'IRK')) && strcmp(ocp.model.dyn_ext_fun_type, 'casadi')
                generate_c_code_implicit_ode(ocp.model, code_gen_opts, model_dir);
            elseif (strcmp(solver_opts.integrator_type, 'GNSF'))
                generate_c_code_gnsf(ocp.model, code_gen_opts, model_dir);
            elseif (strcmp(solver_opts.integrator_type, 'DISCRETE')) && strcmp(ocp.model.dyn_ext_fun_type, 'casadi')
                generate_c_code_disc_dyn(ocp.model, code_gen_opts, model_dir);
            end
            if strcmp(ocp.model.dyn_ext_fun_type, 'generic')
                copyfile( fullfile(pwd, ocp.model.dyn_generic_source), model_dir);
            end

            stage_types = {'initial', 'path', 'terminal'};

            % cost
            cost_types = {cost.cost_type_0, cost.cost_type, cost.cost_type_e};
            cost_ext_fun_types = {cost.cost_ext_fun_type_0, cost.cost_ext_fun_type, cost.cost_ext_fun_type_e};
            cost_dir = fullfile(pwd, ocp.code_export_directory, [ocp.name '_cost']);

            for i = 1:3
                if strcmp(cost_types{i}, 'NONLINEAR_LS')
                    generate_c_code_nonlinear_least_squares( ocp.model, cost_dir, stage_types{i} );

                elseif strcmp(cost_types{i}, 'CONVEX_OVER_NONLINEAR')
                    % TODO
                    error("Convex-over-nonlinear cost is not implemented yet.")

                elseif strcmp(cost_types{i}, 'EXTERNAL')
                    if strcmp(cost_ext_fun_types{i}, 'casadi')
                        generate_c_code_ext_cost(ocp.model, cost_dir, stage_types{i});
                    elseif strcmp(cost_ext_fun_types{i}, 'generic')
                        setup_generic_cost(cost, cost_dir, stage_types{i})
                    else
                        error('Unknown value for cost_ext_fun_types %s', cost_ext_fun_types{i});
                    end
                end
            end


            % constraints
            constraints_types = {constraints.constr_type_0, constraints.constr_type, constraints.constr_type_e};
            constraints_dims = {dims.nh_0, dims.nh, dims.nh_e};
            constraints_dir = fullfile(pwd, ocp.code_export_directory, [ocp.name '_constraints']);

            for i = 1:3
                if strcmp(constraints_types{i}, 'BGH') && constraints_dims{i} > 0
                    generate_c_code_nonlinear_constr( ocp.model, constraints_dir, stage_types{i} );
                end
            end
        end

        function render_templates(self)
            acados_root_dir = getenv('ACADOS_INSTALL_DIR');
            acados_template_folder = fullfile(acados_root_dir,...
                                  'interfaces', 'acados_template', 'acados_template');

            %% check if t_renderer is available -> download if not
            if ispc()
                t_renderer_location = fullfile(acados_root_dir, 'bin','t_renderer.exe');
            else
                t_renderer_location = fullfile(acados_root_dir, 'bin','t_renderer');
            end

            if ~exist( t_renderer_location, 'file' )
                set_up_t_renderer( t_renderer_location )
            end

            %% load json data
            acados_ocp = loadjson(fileread(self.json_file));

            % get model name from json file
            model_name = acados_ocp.model.name;

            %% render templates
            template_dir = fullfile(acados_template_folder, 'c_templates_tera','*');
            matlab_template_dir = fullfile(acados_template_folder, 'c_templates_tera','matlab_templates', '*');
            json_fullfile = fullfile(pwd, self.json_file);
            main_dir = pwd;
            chdir(self.code_export_directory);

            % main
            template_file = 'main.in.c';
            out_file = ['main_', model_name, '.c'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            % main_sim
            template_file = 'main_sim.in.c';
            out_file = ['main_sim_', model_name, '.c'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            % make_mex
            template_file = 'make_mex.in.m';
            out_file = ['make_mex_', model_name, '.m'];
            render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

            % MEX constructor
            template_file = 'acados_mex_create.in.c';
            out_file = ['acados_mex_create_', model_name, '.c'];
            render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

            % MEX destructor
            template_file = 'acados_mex_free.in.c';
            out_file = ['acados_mex_free_', model_name, '.c'];
            render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

            % MEX solve
            template_file = 'acados_mex_solve.in.c';
            out_file = ['acados_mex_solve_', model_name, '.c'];
            render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

            % MEX set
            template_file = 'acados_mex_set.in.c';
            out_file = ['acados_mex_set_', model_name, '.c'];
            render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

            % MEX reset
            template_file = 'acados_mex_reset.in.c';
            out_file = ['acados_mex_reset_', model_name, '.c'];
            render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

            % MEX class
            template_file = 'mex_solver.in.m';
            out_file = [ model_name, '_mex_solver.m'];
            render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

            % solver
            template_file = 'acados_solver.in.h';
            out_file = ['acados_solver_', model_name, '.h'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            template_file = 'acados_solver.in.c';
            out_file = ['acados_solver_', model_name, '.c'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            % sim_solver
            template_file = 'acados_sim_solver.in.c';
            out_file = ['acados_sim_solver_', model_name, '.c'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            template_file = 'acados_sim_solver.in.h';
            out_file = ['acados_sim_solver_', model_name, '.h'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            % headers and custom C-code files
            c_dir = pwd;
            chdir([model_name, '_model']);
            template_file = 'model.in.h';
            out_file = [model_name, '_model.h'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )
            cd(c_dir);

            cost_dir = [model_name, '_cost'];
            if ~(exist(cost_dir, 'dir'))
                mkdir(cost_dir);
            end
            chdir(cost_dir);

            template_file = 'cost.in.h';
            out_file = [model_name, '_cost.h'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )
            cd(c_dir);

            % constraints
            constr_dir = [model_name, '_constraints'];
            if ~(exist(constr_dir, 'dir'))
                mkdir(constr_dir);
            end
            chdir(constr_dir)

            template_file = 'constraints.in.h';
            out_file = [model_name, '_constraints.h'];
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            cd(c_dir);

            % Makefile
            template_file = 'Makefile.in';
            out_file = 'Makefile';
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            % CMake
            template_file = 'CMakeLists.in.txt';
            out_file = 'CMakeLists.txt';
            render_file( json_fullfile, template_dir, template_file, out_file, t_renderer_location )

            if isempty(acados_ocp.simulink_opts)
                disp("not rendering simulink related templates, as simulink_opts are not specified.")
            else
                % S-function
                template_file = 'acados_solver_sfun.in.c';
                out_file = ['acados_solver_sfunction_' , model_name, '.c'];
                render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

                % MATLAB make script
                template_file = 'make_sfun.in.m';
                out_file = 'make_sfun.m';
                render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

                template_file = 'acados_sim_solver_sfun.in.c';
                out_file = ['acados_sim_solver_sfunction_', model_name, '.c'];
                render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )

                template_file = 'make_sfun_sim.in.m';
                out_file = 'make_sfun_sim.m';
                render_file( json_fullfile, matlab_template_dir, template_file, out_file, t_renderer_location )
            end

            fprintf('Successfully rendered acados templates!\n');
            cd(main_dir)
        end

        function dump_to_json(ocp)
            %% remove CasADi objects from model
            model_without_expr = struct();
            model_without_expr.name = ocp.model.name;
            model_without_expr.dyn_ext_fun_type = ocp.model.dyn_ext_fun_type;
            model_without_expr.dyn_generic_source = ocp.model.dyn_generic_source;
            model_without_expr.dyn_disc_fun_jac_hess = ocp.model.dyn_disc_fun_jac_hess;
            model_without_expr.dyn_disc_fun_jac = ocp.model.dyn_disc_fun_jac;
            model_without_expr.dyn_disc_fun = ocp.model.dyn_disc_fun;
            model_without_expr.gnsf_nontrivial_f_LO = ocp.model.gnsf_nontrivial_f_LO;
            model_without_expr.gnsf_purely_linear = ocp.model.gnsf_purely_linear;
            ocp.model = model_without_expr;

            %% post process numerical data (mostly cast scalars to 1-dimensional cells)
            props = fieldnames(ocp.constraints);
            disable_last_warning();  % show warning for struct conversion only once
            for iprop = 1:length(props)
                this_prop = props{iprop};
                % add logic here if you want to do something based on the property's value
                if strcmp(this_prop, 'x0')
                    continue;
                end
                % add logic here if you want to work with select properties
                this_prop_value = ocp.constraints.(this_prop);
                if all(size(this_prop_value) == [1 1])
                    ocp.constraints.(this_prop) = num2cell(ocp.constraints.(this_prop));
                end
            end

            props = fieldnames(ocp.cost);
            for iprop = 1:length(props)
                this_prop = props{iprop};
                % add logic here if you want to work with select properties
                this_prop_value = ocp.cost.(this_prop);
                % add logic here if you want to do something based on the property's value
                if all(size(this_prop_value) == [1, 1])
                    ocp.cost.(this_prop) = num2cell(ocp.cost.(this_prop));
                end
            end

            %% load JSON layout
            acados_folder = getenv('ACADOS_INSTALL_DIR');
            json_layout_filename = fullfile(acados_folder, 'interfaces',...
                                        'acados_matlab_octave', ...
                                        'acados_template_mex', '+acados_template_mex','acados_ocp_layout.json');
            addpath(fullfile(acados_folder, 'external', 'jsonlab'))
            acados_layout = loadjson(fileread(json_layout_filename));

            %% reshape constraints
            constr_layout = acados_layout.constraints;
            fields = fieldnames(constr_layout);
            for i = 1:numel(fields)
                if strcmp(constr_layout.(fields{i}){1}, 'ndarray')
                    property_dim_names = constr_layout.(fields{i}){2};
                    if length(property_dim_names) == 1 % vector
                        this_dims = [1, ocp.dims.(property_dim_names{1})];
                    else % matrix
                        this_dims = [ocp.dims.(property_dim_names{1}), ocp.dims.(property_dim_names{2})];
                    end
                    try
                        ocp.constraints.(fields{i}) = reshape(ocp.constraints.(fields{i}), this_dims);
                    catch e
                        keyboard
                        error(['error while reshaping constraints.' fields{i} ...
                            ' to dimension ' num2str(this_dims), ', got ',...
                            num2str( size(ocp.constraints.(fields{i}) )) , 10,...
                            e.message ]);
                    end
                    if this_dims(1) == 1 && length(property_dim_names) ~= 1 % matrix with 1 row
                        ocp.constraints.(fields{i}) = {ocp.constraints.(fields{i})};
                    end
                end
            end

            %% reshape cost
            cost_layout = acados_layout.cost;
            fields = fieldnames(cost_layout);
            for i = 1:numel(fields)
                if strcmp(cost_layout.(fields{i}){1}, 'ndarray')
                    property_dim_names = cost_layout.(fields{i}){2};
                    if length(property_dim_names) == 1 % vector
                        this_dims = [1, ocp.dims.(property_dim_names{1})];
                    else % matrix
                        this_dims = [ocp.dims.(property_dim_names{1}), ocp.dims.(property_dim_names{2})];
                    end
                    if ~isempty(ocp.cost.(fields{i}))
                        try
                            ocp.cost.(fields{i}) = reshape(ocp.cost.(fields{i}), this_dims);
                        catch e
                            error(['error while reshaping cost.' fields{i} ...
                                ' to dimension ' num2str(this_dims), ', got ',...
                                num2str( size(ocp.cost.(fields{i}) )) , 10,...
                                e.message ]);
                        end
                        if this_dims(1) == 1 && length(property_dim_names) ~= 1 % matrix with 1 row
                            ocp.cost.(fields{i}) = {ocp.cost.(fields{i})};
                        end
                    end
                elseif strcmp(cost_layout.(fields{i}){1}, 'int')
                    ocp.cost.(fields{i}) = ocp.cost.(fields{i}){1};
                end
            end

            %% reshape opts
            opts = ocp.solver_options;
            opts_layout = acados_layout.solver_options;
            fields = fieldnames(opts_layout);
            for i = 1:numel(fields)
                if strcmp(opts_layout.(fields{i}){1}, 'ndarray')
                    property_dim_names = opts_layout.(fields{i}){2};
                    if length(property_dim_names) == 1 % vector
                        this_dims = [1, ocp.dims.(property_dim_names{1})];
                    else % matrix
                        this_dims = [ocp.dims.(property_dim_names{1}), ocp.dims.(property_dim_names{2})];
                    end
                    try
                        opts.(fields{i}) = reshape(opts.(fields{i}), this_dims);
                    catch e
                        error(['error while reshaping opts.' fields{i} ...
                            ' to dimension ' num2str(this_dims), ', got ',...
                            num2str( size(opts.(fields{i}) )) , 10,...
                            e.message ]);
                    end
                    if this_dims(1) == 1 && length(property_dim_names) ~= 1 % matrix with 1 row
                        opts.(fields{i}) = {opts.(fields{i})};
                    end
                end
            end
            opts.time_steps = reshape(num2cell(opts.time_steps), [1, ocp.dims.N]);
            opts.sim_method_num_stages = reshape(num2cell(opts.sim_method_num_stages), [1, ocp.dims.N]);
            opts.sim_method_num_steps = reshape(num2cell(opts.sim_method_num_steps), [1, ocp.dims.N]);
            opts.sim_method_jac_reuse = reshape(num2cell(opts.sim_method_jac_reuse), [1, ocp.dims.N]);

            ocp.solver_options = opts;

            % parameter values
            try
                ocp.parameter_values = reshape(num2cell(ocp.parameter_values), [1, ocp.dims.np]);
            catch e
                error(['error while reshaping parameter_values'  ...
                        ' to dimension ' num2str([1, ocp.dims.np]) ', got ',...
                        num2str(size(ocp.parameter_values)) , 10,...
                        e.message ]);
            end
            %% dump JSON file
            ocp_json_struct = orderfields(ocp.struct());
            ocp_json_struct.dims = orderfields(ocp_json_struct.dims.struct());
            ocp_json_struct.cost = orderfields(ocp_json_struct.cost.struct());
            ocp_json_struct.constraints = orderfields(ocp_json_struct.constraints.struct());
            ocp_json_struct.solver_options = orderfields(ocp_json_struct.solver_options.struct());

            % add compilation information to json
            libs = loadjson(fileread(fullfile(acados_folder, 'lib', 'link_libs.json')));
            ocp_json_struct.acados_link_libs = orderfields(libs);
            if ismac
                ocp_json_struct.os = 'mac';
            elseif isunix
                ocp_json_struct.os = 'unix';
            else
                ocp_json_struct.os = 'pc';
            end

            json_string = savejson('', ocp_json_struct, 'ForceRootName', 0);

            fid = fopen(ocp.json_file, 'w');
            if fid == -1, error('Cannot create JSON file'); end
            fwrite(fid, json_string, 'char');
            fclose(fid);
        end

    end
end

