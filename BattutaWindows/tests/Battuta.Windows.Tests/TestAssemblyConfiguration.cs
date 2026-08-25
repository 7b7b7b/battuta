// WPF owns process-wide input, font, and resource state even when each test
// creates an isolated STA thread. Running separate UI test classes in parallel
// can therefore deadlock presentation initialization or mouse capture.
[assembly: Xunit.v3.Parallelization(Mode = Xunit.Sdk.ParallelMode.None)]
