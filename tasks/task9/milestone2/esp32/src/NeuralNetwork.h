#pragma once
#include <Arduino.h>
#include <math.h>

// ─── Topology ────────────────────────────────────────────────────────────────
// Inputs  : 4  (bird_y_norm, bird_vy_norm, dx_norm, dy_norm)
// Hidden  : 4  (tanh activation)
// Output  : 1  (sigmoid → flap if > 0.5)
// ─────────────────────────────────────────────────────────────────────────────
#define NN_INPUTS  4
#define NN_HIDDEN  4
#define NN_OUTPUTS 1

// Total weight/bias count (for serialisation / mutation)
// W0: INPUTS*HIDDEN  B0: HIDDEN  W1: HIDDEN*OUTPUTS  B1: OUTPUTS
#define NN_W0_SIZE (NN_INPUTS  * NN_HIDDEN)
#define NN_B0_SIZE (NN_HIDDEN)
#define NN_W1_SIZE (NN_HIDDEN  * NN_OUTPUTS)
#define NN_B1_SIZE (NN_OUTPUTS)
#define NN_PARAM_COUNT (NN_W0_SIZE + NN_B0_SIZE + NN_W1_SIZE + NN_B1_SIZE)

class NeuralNetwork {
public:
    // Weights and biases stored as flat 1-D arrays for cache efficiency
    float w0[NN_W0_SIZE];   // input→hidden  [hidden][input]  row-major
    float b0[NN_B0_SIZE];   // hidden bias
    float w1[NN_W1_SIZE];   // hidden→output [output][hidden] row-major
    float b1[NN_B1_SIZE];   // output bias

    // Randomise all weights using Xavier initialisation
    void randomise();

    // Forward pass — returns true if the network decides to flap
    bool forward(float bird_y_norm,
                 float bird_vy_norm,
                 float dx_norm,
                 float dy_norm) const;

    // Copy weights/biases from another network
    void copyFrom(const NeuralNetwork& src);

    // Apply Gaussian mutation with the given standard deviation
    void mutate(float std_dev);

private:
    static inline float relu(float x)    { return x > 0.0f ? x : 0.0f; }
    static inline float tanhf_(float x)  { return tanhf(x); }
    static inline float sigmoid(float x) { return 1.0f / (1.0f + expf(-x)); }
};
