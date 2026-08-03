# iOS engine bake-off

Status: measurements pending on the physical iPhone 17

The deprecated native app establishes the MLX reference range for this model
class: roughly 18–22 decode tok/s, 60–360 warm prompt tok/s, and 4.2 GB peak
footprint. The v0 decision compares MLX Swift and llama.cpp Metal on the same
iPhone, OS build, rendered prompt, sampling settings, and local model artifacts.

The final record will include time to first token, prompt tok/s, decode tok/s,
peak footprint, device/OS, exact artifact revisions, thermal observations, and
the rationale. llama.cpp must match or beat the MLX baseline to justify a
single-engine iOS v0; otherwise iOS remains on MLX while Android uses llama.cpp.
