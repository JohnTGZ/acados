from acados_template import *
import acados_template as at
import numpy as nmp
from ctypes import *
import matplotlib
import matplotlib.pyplot as plt
import scipy.linalg

CODE_GEN = 1
FORMULATION = 1 # 0 for hexagon 1 for sphere 2 SCQP sphere

i_d_ref = 1.484
i_q_ref = 1.429
w_val   = 200

i_d_ref = -10
i_q_ref = 20
w_val   = 300

# fitted psi_d map
def psi_d_num(x,y):
    #    This function was generated by the Symbolic Math Toolbox version 8.0.
    #    07-Feb-2018 23:07:49

    psi_d_expression = x*(-4.215858085639979e-3) + \
            exp(y**2*(-8.413493151721978e-5))*atan(x*1.416834085282644e-1)*8.834738694115108e-1

    return psi_d_expression

def psi_q_num(x,y):
    #    This function was generated by the Symbolic Math Toolbox version 8.0.
    #    07-Feb-2018 23:07:50

    psi_q_expression = y*1.04488335702649e-2+exp(x**2*(-1.0/7.2e1))*atan(y)*6.649036351062812e-2

    return psi_q_expression

psi_d_ref = psi_d_num(i_d_ref, i_q_ref)
psi_q_ref = psi_q_num(i_d_ref, i_q_ref)

# compute steady-state u
Rs      = 0.4
u_d_ref = Rs*i_d_ref - w_val*psi_q_ref
u_q_ref = Rs*i_q_ref + w_val*psi_d_ref

def export_dae_model():
    
    model_name = 'rsm'

    # constants
    theta = 0.0352
    Rs = 0.4
    m_load = 0.0
    J = nmp.array([[0, -1], [1, 0]])

    # set up states 
    psi_d = SX.sym('psi_d')
    psi_q = SX.sym('psi_q')
    x = vertcat(psi_d, psi_q)

    # set up controls 
    u_d = SX.sym('u_d')
    u_q = SX.sym('u_q')
    u = vertcat(u_d, u_q)

    # set up algebraic variables 
    i_d = SX.sym('i_d')
    i_q = SX.sym('i_q')
    z = vertcat(i_d, i_q)
    
    # set up xdot 
    psi_d_dot = SX.sym('psi_d_dot')
    psi_q_dot = SX.sym('psi_q_dot')
    xdot = vertcat(psi_d_dot, psi_q_dot)

    # set up parameters
    w      = SX.sym('w') # speed
    dist_d = SX.sym('dist_d') # d disturbance
    dist_q = SX.sym('dist_q') # q disturbance
    p      = vertcat(w, dist_d, dist_q)

    # build flux expression
    Psi = vertcat(psi_d_num(i_d, i_q), psi_q_num(i_d, i_q))
    
    # dynamics     
    f_impl = vertcat(   psi_d_dot - u_d + Rs*i_d - w*psi_q - dist_d, \
                        psi_q_dot - u_q + Rs*i_q + w*psi_d - dist_q, \
                        psi_d - Psi[0], \
                        psi_q - Psi[1])

    model = acados_dae()

    model.f_impl_expr = f_impl
    model.f_expl_expr = []
    model.x = x
    model.xdot = xdot
    model.u = u
    model.z = z
    model.p = p
    model.name = model_name

    return model 

def export_voltage_sphere_con(u_max):
    
    con_name = 'v_sphere'

    # set up states 
    psi_d = SX.sym('psi_d')
    psi_q = SX.sym('psi_q')
    x = vertcat(psi_d, psi_q)

    # set up controls 
    u_d = SX.sym('u_d')
    u_q = SX.sym('u_q')
    u = vertcat(u_d, u_q)

    # voltage sphere
    constraint = acados_constraint()

    constraint.expr = u_d**2 + u_q**2  
    # constraint.expr = u_d + u_q  
    constraint.x = x
    constraint.u = u
    constraint.nc = 1
    constraint.name = con_name

    return constraint 

def get_general_constraints_DC(u_max):
    
    # polytopic constraint on the input
    r = u_max

    x1 = r
    y1 = 0
    x2 = r*cos(pi/3)
    y2 = r*sin(pi/3)

    q1 = -(y2 - y1/x1*x2)/(1-x2/x1)
    m1 = -(y1 + q1)/x1

    # q1 <= uq + m1*ud <= -q1
    # q1 <= uq - m1*ud <= -q1

    # box constraints
    m2 = 0
    q2 = r*sin(pi/3)
    # -q2 <= uq  <= q2

    # form D and C matrices 
    # (acados C interface works with column major format)
    D = nmp.transpose(nmp.array([[1, m1],[1, -m1]]))
    # D = nmp.array([[1, m1],[1, -m1]])
    # TODO(andrea): ???
    # D = nmp.transpose(nmp.array([[m1, 1],[-m1, 1]]))
    D = nmp.array([[m1, 1],[-m1, 1]])
    C = nmp.transpose(nmp.array([[0, 0], [0, 0]]))
    
    ug  = nmp.array([-q1, -q1])
    lg  = nmp.array([+q1, +q1])
    lbu = nmp.array([-q2]) 
    ubu = nmp.array([+q2]) 
    
    res = dict()
    res["D"] = D
    res["C"] = C
    res["lg"] = lg
    res["ug"] = ug
    res["lbu"] = lbu
    res["ubu"] = ubu

    return res 

# create render arguments
ra = ocp_nlp_render_arguments()

udc = 580
u_max = 2/3*udc

# export model 
model = export_dae_model()

# export constraint description
constraint = export_voltage_sphere_con(u_max)

# set model_name 
ra.model_name = model.name

if FORMULATION == 1:
    # constraints name 
    ra.con_h_name = constraint.name

if FORMULATION == 2:
    # constraints name 
    ra.con_h_name = constraint.name
    ra.con_p_name = constraint.name

# Ts  = 0.0016
# Ts  = 0.0012
Ts  = 0.0008
# Ts  = 0.0004

nx  = model.x.size()[0]
nu  = model.u.size()[0]
nz  = model.z.size()[0]
np  = model.p.size()[0]
ny  = nu + nx
nyN = nx
N   = 2
Tf  = N*Ts

# set ocp_nlp_dimensions
nlp_dims      = ra.dims
nlp_dims.nx   = nx 
nlp_dims.nz   = nz 
nlp_dims.ny   = ny 
nlp_dims.nyN  = nyN 
nlp_dims.nbx  = 0
# nlp_dims.nbu  = 0 

if FORMULATION == 0:
    nlp_dims.nbu  = 1 
    nlp_dims.ng   = 2 

if FORMULATION == 1:
    nlp_dims.ng  = 0 
    nlp_dims.nh  = 1

if FORMULATION == 2:
    nlp_dims.ng  = 0 
    nlp_dims.npd  = 1
    nlp_dims.nh  = 1
    nlp_dims.nhN = 0

# nlp_dims.nbu  = 2 
# nlp_dims.ng   = 2 
# nlp_dims.ng   = 0 
nlp_dims.ngN  = 0 
nlp_dims.nbxN = 0
nlp_dims.nu   = nu
nlp_dims.np   = np
nlp_dims.N    = N
# nlp_dims.npdN = 0
# nlp_dims.nh  = 1

# set weighting matrices
nlp_cost = ra.cost
Q = nmp.eye(nx)
Q[0,0] = 5e2*Tf/N
Q[1,1] = 5e2*Tf/N

R = nmp.eye(nu)
R[0,0] = 1e-4*Tf/N
R[1,1] = 1e-4*Tf/N
# R[0,0] = 1e1
# R[1,1] = 1e1

nlp_cost.W = scipy.linalg.block_diag(Q, R) 

Vx = nmp.zeros((ny, nx))
Vx[0,0] = 1.0
Vx[1,1] = 1.0

nlp_cost.Vx = Vx

Vu = nmp.zeros((ny, nu))
Vu[2,0] = 1.0
Vu[3,1] = 1.0
nlp_cost.Vu = Vu

Vz = nmp.zeros((ny, nz))
Vz[0,0] = 0.0
Vz[1,1] = 0.0

nlp_cost.Vz = Vz

QN = nmp.eye(nx)
QN[0,0] = 1e-3
QN[1,1] = 1e-3
nlp_cost.WN = QN 

VxN = nmp.zeros((ny, nx))
VxN[0,0] = 1.0
VxN[1,1] = 1.0

nlp_cost.VxN = VxN

nlp_cost.yref  = nmp.zeros((ny, 1))
nlp_cost.yref[0]  = psi_d_ref 
nlp_cost.yref[1]  = psi_q_ref 
nlp_cost.yref[2]  = u_d_ref
nlp_cost.yref[3]  = u_q_ref
nlp_cost.yrefN = nmp.zeros((nyN, 1))
nlp_cost.yrefN[0]  = psi_d_ref
nlp_cost.yrefN[1]  = psi_q_ref

# get D and C
res = get_general_constraints_DC(u_max)
D = res["D"]
C = res["C"]
lg = res["lg"]
ug = res["ug"]
lbu = res["lbu"]
ubu = res["ubu"]

# setting bounds
# lbu <= u <= ubu and lbx <= x <= ubx
nlp_con = ra.constraints
# nlp_con.idxbu = nmp.array([0, 1])
# nlp_con.lbu = nmp.array([-u_max, -u_max])
# nlp_con.ubu = nmp.array([+u_max, +u_max])
nlp_con.idxbu = nmp.array([1])

nlp_con.lbu = lbu
nlp_con.ubu = ubu

if FORMULATION > 0:
    nlp_con.lh = nmp.array([-1.0e8])
    nlp_con.uh = nmp.array([u_max**2])

nlp_con.x0 = nmp.array([0.0, -0.0])

if FORMULATION == 0:
    # setting general constraints
    # lg <= D*u + C*u <= ug
    nlp_con.D   = D
    nlp_con.C   = C 
    nlp_con.lg  = lg
    nlp_con.ug  = ug 
    # nlp_con.CN  = ... 
    # nlp_con.lgN = ... 
    # nlp_con.ugN = ...
else:
    nlp_con.D   = nmp.zeros((2,2))
    nlp_con.C   = nmp.zeros((2,2))
    nlp_con.lg  = 0*nmp.array([-1.0e8])
    nlp_con.ug  = 0*nmp.array([u_max])

# setting parameters
nlp_con.p = nmp.array([w_val, 0.0, 0.0])

# set constants
ra.constants = []

# set QP solver
ra.solver_config.qp_solver = 'PARTIAL_CONDENSING_HPIPM'
# ra.solver_config.qp_solver = 'FULL_CONDENSING_HPIPM'
# ra.solver_config.qp_solver = 'FULL_CONDENSING_QPOASES'
ra.solver_config.hessian_approx = 'GAUSS_NEWTON'
# ra.solver_config.hessian_approx = 'EXACT'
# ra.solver_config.integrator_type = 'ERK'
ra.solver_config.integrator_type = 'IRK'

# set prediction horizon
ra.solver_config.tf = Tf
ra.solver_config.nlp_solver_type = 'SQP_RTI'
# ra.solver_config.nlp_solver_type = 'SQP'

# set header path
ra.acados_include_path = '/usr/local/include'
ra.acados_lib_path = '/usr/local/lib'

if CODE_GEN == 1:
    if FORMULATION == 0:
        generate_solver(model, ra)
    if FORMULATION == 1:
        generate_solver(model, ra, con_h=constraint)
    if FORMULATION == 2:
        generate_solver(model, ra, con_h=constraint, con_p=constraint)

# make 
os.chdir('c_generated_code')
os.system('make')
os.system('make shared_lib')
os.chdir('..')

acados   = CDLL('c_generated_code/acados_solver_rsm.so')

acados.acados_create()

nlp_opts = acados.acados_get_nlp_opts()
nlp_dims = acados.acados_get_nlp_dims()
nlp_config = acados.acados_get_nlp_config()
nlp_out = acados.acados_get_nlp_out()
nlp_in = acados.acados_get_nlp_in()

# closed loop simulation TODO(add proper simulation)
Nsim = 100

x0 = cast(create_string_buffer(nx*sizeof(c_double)), c_void_p)
u0 = cast(create_string_buffer(nu*sizeof(c_double)), c_void_p)

simX = nmp.ndarray((Nsim, nx))
simU = nmp.ndarray((Nsim, nu))

for i in range(Nsim):
    acados.acados_solve()

    # get solution
    field_name = "x"
    arg = field_name.encode('utf-8')
    x0 = cast((x0), c_void_p)
    acados.ocp_nlp_out_get(nlp_config, nlp_dims, nlp_out, 0, field_name, x0)
    x0 = cast((x0), POINTER(c_double))

    field_name = "u"
    arg = field_name.encode('utf-8')
    u0 = cast((u0), c_void_p)
    acados.ocp_nlp_out_get(nlp_config, nlp_dims, nlp_out, 0, field_name, u0)
    u0 = cast((u0), POINTER(c_double))

    for j in range(nx):
        simX[i,j] = x0[j]

    for j in range(nu):
        simU[i,j] = u0[j]
    
    # import pdb; pdb.set_trace()
    field_name = "u"
    # update initial condition
    field_name = "x"
    arg = field_name.encode('utf-8')
    x0 = cast((x0), c_void_p)
    acados.ocp_nlp_out_get(nlp_config, nlp_dims, nlp_out, 1, field_name, x0)

    field_name = "lbx"
    arg = field_name.encode('utf-8')
    acados.ocp_nlp_constraints_model_set(nlp_config, nlp_dims, nlp_in, 0, arg, x0)
    field_name = "ubx"
    arg = field_name.encode('utf-8')
    acados.ocp_nlp_constraints_model_set(nlp_config, nlp_dims, nlp_in, 0, arg, x0)

# plot results
t = nmp.linspace(0.0, Ts*Nsim, Nsim)
plt.subplot(4, 1, 1)
plt.step(t, simU[:,0], 'r')
plt.plot([0, Ts*Nsim], [nlp_cost.yref[2], nlp_cost.yref[2]], '--')
plt.title('closed-loop simulation')
plt.ylabel('u_d')
plt.xlabel('t')
plt.grid(True)
plt.subplot(4, 1, 2)
plt.step(t, simU[:,1], 'r')
plt.plot([0, Ts*Nsim], [nlp_cost.yref[3], nlp_cost.yref[3]], '--')
plt.ylabel('u_q')
plt.xlabel('t')
plt.grid(True)
plt.subplot(4, 1, 3)
plt.plot(t, simX[:,0])
plt.plot([0, Ts*Nsim], [nlp_cost.yref[0], nlp_cost.yref[0]], '--')
plt.ylabel('psi_d')
plt.xlabel('t')
plt.grid(True)
plt.subplot(4, 1, 4)
plt.plot(t, simX[:,1])
plt.plot([0, Ts*Nsim], [nlp_cost.yref[1], nlp_cost.yref[1]], '--')
plt.ylabel('psi_q')
plt.xlabel('t')
plt.grid(True)

# plot hexagon
r = u_max

x1 = r
y1 = 0
x2 = r*cos(pi/3)
y2 = r*sin(pi/3)

q1 = -(y2 - y1/x1*x2)/(1-x2/x1)
m1 = -(y1 + q1)/x1

# q1 <= uq + m1*ud <= -q1
# q1 <= uq - m1*ud <= -q1

# box constraints
m2 = 0
q2 = r*sin(pi/3)
# -q2 <= uq  <= q2

plt.figure()
plt.plot(simU[:,0], simU[:,1], 'o')
plt.xlabel('ud')
plt.ylabel('uq')
ud = nmp.linspace(-1.5*u_max, 1.5*u_max, 100)
plt.plot(ud, -m1*ud -q1)
plt.plot(ud, -m1*ud +q1)
plt.plot(ud, +m1*ud -q1)
plt.plot(ud, +m1*ud +q1)
plt.plot(ud, -q2*nmp.ones((100, 1)))
plt.plot(ud, q2*nmp.ones((100, 1)))
plt.grid(True)
ax = plt.gca()
ax.set_xlim([-1.5*u_max, 1.5*u_max])
ax.set_ylim([-1.5*u_max, 1.5*u_max])
plt.show()

# free memory
acados.acados_free()


