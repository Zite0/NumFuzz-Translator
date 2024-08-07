@rnd64 = float<ieee_64, up>;
@rnd32 = float<ieee_32, up>;
r  = ((a2 * (x * x)) + (a1 * x)) + a0;
z0 rnd64 = ((a2 * (x * x)) + (a1 * x)) + a0;
z = rnd32(z0);

# the logical formula that Gappa will try (and succeed) to prove
{ x in [0.1,1000] /\ a0 in [0.1,1000]
  /\ a1 in [0.1,1000] /\ a2 in [0.1,1000] -> |(z - r) / r| in ? }
