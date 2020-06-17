////////////////////////////////////////////////////////////////////////////////
//
// opencl_euler_cromer.cl
//
// OpenCL Peridynamics kernels for an Euler Cromer integrator
//
// Based on code from Copyright (c) Farshid Mossaiby, 2016, 2017. Adapted for python.
//
////////////////////////////////////////////////////////////////////////////////

// Includes, project
#include "opencl_enable_fp64.cl"

// Macros
#define DPN 3
// MAX_HORIZON_LENGTH, PD_R, PD_DX, PD_DT, PD_RHO, PD_NODE_NO, PD_DPN_NODE_NO will be defined on JIT compiler's command line

// Utility functions
// Volume correction factor
double beta(const double xi)
{
	if (xi <= PD_R - PD_DX / 2.00)
	{
		return 1.00;
	}

	else if (xi <= PD_R + PD_DX / 2.00)
	{
		return (PD_R + PD_DX / 2.00 - xi) / (PD_DX);
	}

	else
	{
		return 0.00;
	}
}

// Update displacements
__kernel void
	UpdateDisplacement(
        __global double const *Udn,
        __global double *Un,
		__global int const *BCTypes,
		__global double const *BCValues,
		double DISPLACEMENT_LOAD_SCALE
	)
{
	const int i = get_global_id(0);

	if (i < PD_DPN_NODE_NO)
	{
		Un[i] = (BCTypes[i] == 2 ? (Un[i] + PD_DT * Udn[i]) : (Un[i] + DISPLACEMENT_LOAD_SCALE * BCValues[i]));
	}
}


// Calculate force using Un, force BC applied at end here
__kernel void
	CalcBondForce(
        __global double *Uddn,
        __global double const *Udn,
        __global double const *Un,
		__global double * Node_Forces,
        __global double const *Vols,
		__global int const *Horizons,
		__global double const *Nodes,
		__global double const *Stiffnesses,
		__global int const *FCTypes,
		__global double const *FCValues,
		double FORCE_LOAD_SCALE

	)
{
	const int i = get_global_id(0);

	double f0 = 0.00;
	double f1 = 0.00;
	double f2 = 0.00;

	if (i < PD_NODE_NO)
	{
		for (int j = 0; j < MAX_HORIZON_LENGTH; j++)
		{
			const int n = Horizons[MAX_HORIZON_LENGTH * i + j];

			if (n != -1)
			{
				const double xi_x = Nodes[DPN * n + 0] - Nodes[DPN * i + 0];  // Optimize later, doesn't need to be done every time
				const double xi_y = Nodes[DPN * n + 1] - Nodes[DPN * i + 1];
				const double xi_z = Nodes[DPN * n + 2] - Nodes[DPN * i + 2];


				const double xi_eta_x = Un[DPN * n + 0] - Un[DPN * i + 0] + xi_x;
				const double xi_eta_y = Un[DPN * n + 1] - Un[DPN * i + 1] + xi_y;
				const double xi_eta_z = Un[DPN * n + 2] - Un[DPN * i + 2] + xi_z;

				const double xi = sqrt(xi_x * xi_x + xi_y * xi_y + xi_z * xi_z);
				const double y = sqrt(xi_eta_x * xi_eta_x + xi_eta_y * xi_eta_y + xi_eta_z * xi_eta_z);
                const double y_xi = (y - xi);

				const double cx = xi_eta_x / y;
				const double cy = xi_eta_y / y;
				const double cz = xi_eta_z / y;

				const double _E = Stiffnesses[MAX_HORIZON_LENGTH * i + j];
                const double _A = Vols[n];
				const double _L = xi;

				const double _EAL = _E * _A / _L;

                f0 += _EAL * cx * y_xi;
                f1 += _EAL * cy * y_xi;
                f2 += _EAL * cz * y_xi;
			}
		}

		// Add body forces
		f0 = (FCTypes[DPN*i + 0] == 2 ? f0 : (f0 + FORCE_LOAD_SCALE * FCValues[DPN * i + 0]));
		f1 = (FCTypes[DPN*i + 1] == 2 ? f1 : (f1 + FORCE_LOAD_SCALE * FCValues[DPN * i + 1]));
		f2 = (FCTypes[DPN*i + 2] == 2 ? f2 : (f2 + FORCE_LOAD_SCALE * FCValues[DPN * i + 2]));

		// Update Node forces for plotting
		Node_Forces[DPN * i + 0] = f0;
        Node_Forces[DPN * i + 1] = f1;
        Node_Forces[DPN * i + 2] = f2;

        // Update accelerations
		Uddn[DPN * i + 0] = (f0 - PD_ETA * Udn[DPN * i + 0]) / PD_RHO;
		Uddn[DPN * i + 1] = (f1 - PD_ETA * Udn[DPN * i + 1]) / PD_RHO;
		Uddn[DPN * i + 2] = (f2 - PD_ETA * Udn[DPN * i + 2]) / PD_RHO;
	}
}

// Update velocities
__kernel void
	UpdateVelocity(
        __global double *Udn,
        __global double const *Uddn
	)
{
	const int i = get_global_id(0);

	if (i < PD_DPN_NODE_NO)
	{   
        Udn[i] += Uddn[i] * PD_DT;
	}
}


__kernel void
	CheckBonds(
		__global int *Horizons,
		__global double const *Un,
		__global double const *Nodes,
		__global double const *FailStretches
	)
{
	const int i = get_global_id(0);
	const int j = get_global_id(1);

	if ((i < PD_NODE_NO) && (j >= 0) && (j < MAX_HORIZON_LENGTH))
	{
		const int n = Horizons[i * MAX_HORIZON_LENGTH + j];

		if (n != -1)
		{
			const double xi_x = Nodes[DPN * n + 0] - Nodes[DPN * i + 0];  // Optimize later
			const double xi_y = Nodes[DPN * n + 1] - Nodes[DPN * i + 1];
			const double xi_z = Nodes[DPN * n + 2] - Nodes[DPN * i + 2];

			const double xi_eta_x = Un[DPN * n + 0] - Un[DPN * i + 0] + xi_x;
			const double xi_eta_y = Un[DPN * n + 1] - Un[DPN * i + 1] + xi_y;
			const double xi_eta_z = Un[DPN * n + 2] - Un[DPN * i + 2] + xi_z;

			const double xi = sqrt(xi_x * xi_x + xi_y * xi_y + xi_z * xi_z);
			const double y = sqrt(xi_eta_x * xi_eta_x + xi_eta_y * xi_eta_y + xi_eta_z * xi_eta_z);

			const double PD_S0 = FailStretches[i * MAX_HORIZON_LENGTH + j];

			const double s = (y - xi) / xi;

			// Check for state of the bond

			if (s > PD_S0)
			{
				Horizons[i * MAX_HORIZON_LENGTH + j] = -1;  // Break the bond
			}
		}
	}
}

__kernel void
	CalculateDamage(
		__global double *Phi,
		__global int const *Horizons,
		__global int const *HorizonLengths
	)
{
	const int i = get_global_id(0);

	if (i < PD_NODE_NO)
	{
		int active_bonds = 0;

		for (int j = 0; j < MAX_HORIZON_LENGTH; j++)
		{
			if (Horizons[MAX_HORIZON_LENGTH * i + j] != -1)
			{
				active_bonds++;
			}
		}

		Phi[i] = 1.00 - (double) active_bonds / (double) (HorizonLengths[i]);
	}
}