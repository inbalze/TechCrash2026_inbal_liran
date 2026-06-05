#include "NeuralNetwork.h"

// ─── Gaussian RNG (Box-Muller) ────────────────────────────────────────────────
static float gaussian(float mean, float std_dev) {
    // Box-Muller transform
    float u1 = (float)(random(1, 1000001)) / 1000000.0f;
    float u2 = (float)(random(1, 1000001)) / 1000000.0f;
    float z  = sqrtf(-2.0f * logf(u1)) * cosf(2.0f * (float)M_PI * u2);
    return mean + std_dev * z;
}

// ─── Xavier initialisation ────────────────────────────────────────────────────
void NeuralNetwork::randomise() {
    float scale0 = sqrtf(2.0f / (NN_INPUTS + NN_HIDDEN));
    float scale1 = sqrtf(2.0f / (NN_HIDDEN + NN_OUTPUTS));

    for (int i = 0; i < NN_W0_SIZE; i++) w0[i] = gaussian(0.0f, scale0);
    for (int i = 0; i < NN_B0_SIZE; i++) b0[i] = 0.0f;
    for (int i = 0; i < NN_W1_SIZE; i++) w1[i] = gaussian(0.0f, scale1);
    for (int i = 0; i < NN_B1_SIZE; i++) b1[i] = 0.0f;
}

// ─── Forward pass ─────────────────────────────────────────────────────────────
bool NeuralNetwork::forward(float bird_y_norm,
                             float bird_vy_norm,
                             float dx_norm,
                             float dy_norm) const {
    float input[NN_INPUTS] = { bird_y_norm, bird_vy_norm, dx_norm, dy_norm };
    float hidden[NN_HIDDEN];

    // Layer 0: input → hidden (ReLU activation — matches FPGA nn_accelerator.sv)
    for (int h = 0; h < NN_HIDDEN; h++) {
        float sum = b0[h];
        for (int i = 0; i < NN_INPUTS; i++) {
            sum += w0[h * NN_INPUTS + i] * input[i];
        }
        hidden[h] = relu(sum);
    }

    // Layer 1: hidden → output (sigmoid activation)
    float out = b1[0];
    for (int h = 0; h < NN_HIDDEN; h++) {
        out += w1[h] * hidden[h];
    }
    float output = sigmoid(out);

    return output > 0.5f;
}

// ─── Copy ─────────────────────────────────────────────────────────────────────
void NeuralNetwork::copyFrom(const NeuralNetwork& src) {
    memcpy(w0, src.w0, sizeof(w0));
    memcpy(b0, src.b0, sizeof(b0));
    memcpy(w1, src.w1, sizeof(w1));
    memcpy(b1, src.b1, sizeof(b1));
}

// ─── Mutation ─────────────────────────────────────────────────────────────────
void NeuralNetwork::mutate(float std_dev) {
    for (int i = 0; i < NN_W0_SIZE; i++) w0[i] += gaussian(0.0f, std_dev);
    for (int i = 0; i < NN_B0_SIZE; i++) b0[i] += gaussian(0.0f, std_dev);
    for (int i = 0; i < NN_W1_SIZE; i++) w1[i] += gaussian(0.0f, std_dev);
    for (int i = 0; i < NN_B1_SIZE; i++) b1[i] += gaussian(0.0f, std_dev);
}
