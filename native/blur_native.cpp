// Native image engine for Blur App. Called from Dart through FFI
// (lib/features/deblur/deblur_native.dart). Keep the exported signatures in
// sync with that file.

#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <onnxruntime_cxx_api.h>
#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#define BLUR_EXPORT extern "C" __attribute__((visibility("default")))

namespace {

enum Method { kSharpen = 0, kFocus = 1, kMotion = 2 };

void set_error(char* err, int err_len, const std::string& message) {
  if (err == nullptr || err_len <= 0) return;
  std::strncpy(err, message.c_str(), static_cast<size_t>(err_len) - 1);
  err[err_len - 1] = '\0';
}

// Unsharp mask: adds back the detail a Gaussian blur of `sigma` removes.
// strength 0..100 maps to an amount of 0..2.
cv::Mat sharpen(const cv::Mat& src, double sigma, double strength) {
  cv::Mat blurred;
  cv::GaussianBlur(src, blurred, cv::Size(0, 0), sigma);
  const double amount = strength / 50.0;
  cv::Mat out;
  cv::addWeighted(src, 1.0 + amount, blurred, -amount, 0.0, out);
  return out;
}

// Out-of-focus blur: a uniform disk, with a soft one-pixel edge.
cv::Mat disk_psf(double radius) {
  const int half = static_cast<int>(std::ceil(radius)) + 1;
  cv::Mat psf(2 * half + 1, 2 * half + 1, CV_32F);
  for (int y = 0; y < psf.rows; y++) {
    for (int x = 0; x < psf.cols; x++) {
      const double d = std::hypot(x - half, y - half);
      psf.at<float>(y, x) =
          static_cast<float>(std::clamp(radius + 0.5 - d, 0.0, 1.0));
    }
  }
  return psf / cv::sum(psf)[0];
}

// Motion blur: a straight line of `length` pixels at `angle_deg`
// (0 = horizontal, counter-clockwise positive).
cv::Mat motion_psf(double length, double angle_deg) {
  const int half = static_cast<int>(std::ceil(length / 2.0)) + 1;
  const double rad = angle_deg * CV_PI / 180.0;
  const double ux = std::cos(rad), uy = -std::sin(rad);
  cv::Mat psf = cv::Mat::zeros(2 * half + 1, 2 * half + 1, CV_32F);
  // Walk the line in fine steps, crediting each sample to the pixel it lands
  // in. A whole-pixel horizontal or vertical length gives an exact box.
  const int samples = static_cast<int>(std::ceil(length * 16.0));
  for (int i = 0; i < samples; i++) {
    const double t = ((i + 0.5) / samples - 0.5) * length;
    const int x = static_cast<int>(std::lround(half + t * ux));
    const int y = static_cast<int>(std::lround(half + t * uy));
    psf.at<float>(y, x) += 1.0f;
  }
  return psf / cv::sum(psf)[0];
}

// Wiener deconvolution of one float channel with a known blur kernel.
// `nsr` is the assumed noise-to-signal ratio: lower restores more detail but
// amplifies noise and ringing.
cv::Mat wiener_channel(const cv::Mat& channel, const cv::Mat& psf, double nsr) {
  // Mirror-pad, then fade the padding to the mean, so the picture has no
  // hard edge where the FFT wraps round. Without this, edges ring across the
  // whole image at higher strengths.
  const int pad = std::max(3 * std::max(psf.rows, psf.cols), 32);
  const int rows = cv::getOptimalDFTSize(channel.rows + 2 * pad);
  const int cols = cv::getOptimalDFTSize(channel.cols + 2 * pad);
  cv::Mat padded;
  cv::copyMakeBorder(channel, padded, pad, rows - channel.rows - pad, pad,
                     cols - channel.cols - pad, cv::BORDER_REFLECT);
  const auto window = [pad](int size, int image_size) {
    // 1 over the picture, easing to 0 at the far edge of the padding.
    std::vector<float> w(static_cast<size_t>(size));
    const int trailing = size - image_size - pad;
    for (int i = 0; i < size; i++) {
      double d = 1.0;
      if (i < pad) d = (i + 0.5) / pad;
      if (i >= pad + image_size) d = (size - i - 0.5) / trailing;
      w[static_cast<size_t>(i)] =
          static_cast<float>(0.5 - 0.5 * std::cos(CV_PI * d));
    }
    return w;
  };
  const std::vector<float> wy = window(rows, channel.rows);
  const std::vector<float> wx = window(cols, channel.cols);
  const float mean = static_cast<float>(cv::mean(channel)[0]);
  for (int y = 0; y < rows; y++) {
    float* row = padded.ptr<float>(y);
    for (int x = 0; x < cols; x++) {
      const float w = wy[static_cast<size_t>(y)] * wx[static_cast<size_t>(x)];
      row[x] = mean + (row[x] - mean) * w;
    }
  }

  // Kernel centred on the origin (wrapping round), so the result is not
  // shifted.
  cv::Mat kernel = cv::Mat::zeros(rows, cols, CV_32F);
  const int cy = psf.rows / 2, cx = psf.cols / 2;
  for (int y = 0; y < psf.rows; y++) {
    for (int x = 0; x < psf.cols; x++) {
      kernel.at<float>((y - cy + rows) % rows, (x - cx + cols) % cols) =
          psf.at<float>(y, x);
    }
  }

  cv::Mat image_f, kernel_f;
  cv::dft(padded, image_f, cv::DFT_COMPLEX_OUTPUT);
  cv::dft(kernel, kernel_f, cv::DFT_COMPLEX_OUTPUT);

  // F = G * conj(H) / (|H|^2 + nsr), scaled by (1 + nsr) so overall
  // brightness is preserved (the kernel sums to 1, so H(0) = 1).
  cv::Mat numerator;
  cv::mulSpectrums(image_f, kernel_f, numerator, 0, true);
  cv::Mat h[2];
  cv::split(kernel_f, h);
  cv::Mat denominator = (h[0].mul(h[0]) + h[1].mul(h[1]) + nsr) / (1.0 + nsr);
  cv::Mat n[2];
  cv::split(numerator, n);
  n[0] /= denominator;
  n[1] /= denominator;
  cv::Mat restored_f;
  cv::merge(n, 2, restored_f);

  cv::Mat restored;
  cv::idft(restored_f, restored, cv::DFT_SCALE | cv::DFT_REAL_OUTPUT);
  return restored(cv::Rect(pad, pad, channel.cols, channel.rows)).clone();
}

cv::Mat deconvolve(const cv::Mat& src, const cv::Mat& psf, double strength) {
  // strength 0..100 maps to nsr 1e-1 (gentle) .. 1e-4 (aggressive).
  const double nsr = std::pow(10.0, -1.0 - 3.0 * strength / 100.0);
  std::vector<cv::Mat> channels;
  cv::split(src, channels);
  cv::parallel_for_(cv::Range(0, static_cast<int>(channels.size())),
                    [&](const cv::Range& range) {
                      for (int i = range.start; i < range.end; i++) {
                        channels[i] = wiener_channel(channels[i], psf, nsr);
                      }
                    });
  cv::Mat out;
  cv::merge(channels, out);
  return out;
}

// Neural models see the picture in square tiles: a whole photo does not fit
// in GPU memory (a 2048 px square already exceeds 8 GB with NAFNet), and
// tiles of one size let the GPU reuse its setup. Neighbouring tiles overlap
// and are cross-faded so no seams show.
constexpr int kTile = 512;
constexpr int kOverlap = 32;

// Start offsets of the tiles along one side of `size` pixels.
std::vector<int> tile_starts(int size) {
  if (size <= kTile) return {0};
  const int count = static_cast<int>(
      std::ceil((size - kOverlap) / static_cast<double>(kTile - kOverlap)));
  std::vector<int> starts(static_cast<size_t>(count));
  for (int i = 0; i < count; i++) {
    starts[static_cast<size_t>(i)] = static_cast<int>(
        std::lround(i * static_cast<double>(size - kTile) / (count - 1)));
  }
  return starts;
}

// Blend weight across a tile side: ramps up over the overlap at each end.
std::vector<float> tile_ramp(int length) {
  std::vector<float> ramp(static_cast<size_t>(length));
  for (int i = 0; i < length; i++) {
    ramp[static_cast<size_t>(i)] =
        std::min({i + 1, length - i, kOverlap}) / static_cast<float>(kOverlap);
  }
  return ramp;
}

// Runs an image-to-image ONNX model over `src` (float 0..1, one channel or
// BGR). The model must take one float tensor 1x3xHxW, RGB 0..1, of any H and
// W, and return one of the same shape. Throws Ort::Exception when the model
// or the chosen device cannot run.
cv::Mat neural_restore(const cv::Mat& src, const char* model_path,
                       bool use_gpu) {
  Ort::Env env(ORT_LOGGING_LEVEL_ERROR, "blur_app");
  Ort::SessionOptions options;
  // Lets weights stored in compressed (quantised) form be unpacked when the
  // model loads; the GPU cannot unpack them itself.
  options.AddConfigEntry("session.disable_quant_qdq", "1");
  if (use_gpu) {
    OrtCUDAProviderOptionsV2* cuda = nullptr;
    Ort::ThrowOnError(Ort::GetApi().CreateCUDAProviderOptions(&cuda));
    // Take only the memory each tile needs instead of doubling the pool.
    const char* keys[] = {"arena_extend_strategy"};
    const char* values[] = {"kSameAsRequested"};
    OrtStatus* status =
        Ort::GetApi().UpdateCUDAProviderOptions(cuda, keys, values, 1);
    if (status == nullptr) {
      status = Ort::GetApi().SessionOptionsAppendExecutionProvider_CUDA_V2(
          options, cuda);
    }
    Ort::GetApi().ReleaseCUDAProviderOptions(cuda);
    Ort::ThrowOnError(status);
  }
  Ort::Session session(env, model_path, options);
  if (session.GetInputCount() != 1 || session.GetOutputCount() != 1) {
    throw std::runtime_error("The model must have one input and one output");
  }
  const Ort::TypeInfo input_type = session.GetInputTypeInfo(0);
  if (input_type.GetTensorTypeAndShapeInfo().GetElementType() !=
      ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
    throw std::runtime_error("The model must take 32-bit float input");
  }
  Ort::AllocatorWithDefaultOptions allocator;
  const auto input_name = session.GetInputNameAllocated(0, allocator);
  const auto output_name = session.GetOutputNameAllocated(0, allocator);
  const char* input_names[] = {input_name.get()};
  const char* output_names[] = {output_name.get()};
  const Ort::MemoryInfo memory =
      Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

  cv::Mat rgb;
  cv::cvtColor(src, rgb,
               src.channels() == 1 ? cv::COLOR_GRAY2RGB : cv::COLOR_BGR2RGB);
  const int tile_h = std::min(kTile, rgb.rows);
  const int tile_w = std::min(kTile, rgb.cols);
  const size_t plane = static_cast<size_t>(tile_h) * tile_w;
  const std::vector<float> ramp_y = tile_ramp(tile_h);
  const std::vector<float> ramp_x = tile_ramp(tile_w);
  cv::Mat tile_weight(tile_h, tile_w, CV_32F);
  for (int y = 0; y < tile_h; y++) {
    for (int x = 0; x < tile_w; x++) {
      tile_weight.at<float>(y, x) =
          ramp_y[static_cast<size_t>(y)] * ramp_x[static_cast<size_t>(x)];
    }
  }
  cv::Mat tile_weight3;
  cv::cvtColor(tile_weight, tile_weight3, cv::COLOR_GRAY2RGB);

  cv::Mat sum = cv::Mat::zeros(rgb.size(), CV_32FC3);
  cv::Mat weight = cv::Mat::zeros(rgb.size(), CV_32FC3);
  std::vector<float> blob(3 * plane);
  const int64_t shape[4] = {1, 3, tile_h, tile_w};
  for (const int top : tile_starts(rgb.rows)) {
    for (const int left : tile_starts(rgb.cols)) {
      const cv::Rect area(left, top, tile_w, tile_h);
      // Interleaved pixels -> one plane per colour, as the model expects.
      std::vector<cv::Mat> planes;
      for (int c = 0; c < 3; c++) {
        planes.emplace_back(tile_h, tile_w, CV_32F, blob.data() + c * plane);
      }
      cv::split(rgb(area), planes);
      Ort::Value input = Ort::Value::CreateTensor<float>(
          memory, blob.data(), blob.size(), shape, 4);
      std::vector<Ort::Value> outputs =
          session.Run(Ort::RunOptions{nullptr}, input_names, &input, 1,
                      output_names, 1);
      const std::vector<int64_t> out_shape =
          outputs[0].GetTensorTypeAndShapeInfo().GetShape();
      if (out_shape != std::vector<int64_t>(shape, shape + 4)) {
        throw std::runtime_error(
            "The model's output is not the same size as its input");
      }
      float* out = outputs[0].GetTensorMutableData<float>();
      std::vector<cv::Mat> out_planes;
      for (int c = 0; c < 3; c++) {
        out_planes.emplace_back(tile_h, tile_w, CV_32F, out + c * plane);
      }
      cv::Mat restored;
      cv::merge(out_planes, restored);
      sum(area) += restored.mul(tile_weight3);
      weight(area) += tile_weight3;
    }
  }
  cv::Mat result = sum / weight;
  cv::cvtColor(result, result,
               src.channels() == 1 ? cv::COLOR_RGB2GRAY : cv::COLOR_RGB2BGR);
  return result;
}

// Why the GPU attempt failed, in words a user can act on.
std::string gpu_failure_reason(const std::string& detail) {
  if (detail.find("cudnn") != std::string::npos ||
      detail.find("cuDNN") != std::string::npos) {
    return "cuDNN 9 is not installed";
  }
  if (detail.find("libonnxruntime_providers_cuda") != std::string::npos ||
      detail.find("libcu") != std::string::npos ||
      detail.find("CUDA failure 100") != std::string::npos ||
      detail.find("no CUDA-capable device") != std::string::npos) {
    return "no usable NVIDIA GPU or CUDA 13 runtime was found";
  }
  if (detail.find("Failed to allocate memory") != std::string::npos ||
      detail.find("out of memory") != std::string::npos) {
    return "the GPU ran out of memory";
  }
  return detail.substr(0, detail.find('\n')).substr(0, 200);
}

// Shared file handling: reads `input_path`, hands the picture to `restore`
// as float 0..1 without its alpha channel, and writes what it returns to
// `output_path` (format chosen by its extension) at the original bit depth
// with the original alpha. Returns 0 on success; otherwise non-zero with a
// message in `err`.
template <typename Restore>
int process_file(const char* input_path, const char* output_path, char* err,
                 int err_len, Restore restore) {
  try {
    cv::Mat image = cv::imread(input_path, cv::IMREAD_UNCHANGED);
    if (image.empty()) {
      set_error(err, err_len,
                std::string("Cannot read image: ") + input_path);
      return 1;
    }
    if (image.depth() != CV_8U && image.depth() != CV_16U) {
      set_error(err, err_len, "Only 8-bit and 16-bit images are supported");
      return 1;
    }
    const int depth = image.depth();
    const double max_value = depth == CV_8U ? 255.0 : 65535.0;

    // Alpha is transparency, not picture content: set it aside untouched.
    cv::Mat alpha;
    if (image.channels() == 4) {
      cv::extractChannel(image, alpha, 3);
      cv::cvtColor(image, image, cv::COLOR_BGRA2BGR);
    }

    cv::Mat work;
    image.convertTo(work, CV_32F, 1.0 / max_value);

    const cv::Mat result = restore(work);

    cv::Mat out;
    result.convertTo(out, depth, max_value);  // saturates to the valid range
    if (!alpha.empty()) {
      std::vector<cv::Mat> channels;
      cv::split(out, channels);
      channels.push_back(alpha);
      cv::merge(channels, out);
    }

    if (!cv::imwrite(output_path, out)) {
      set_error(err, err_len,
                std::string("Cannot write image: ") + output_path);
      return 1;
    }
    return 0;
  } catch (const cv::Exception& e) {
    // imwrite throws for an unrecognised file extension.
    set_error(err, err_len, std::string("Image processing failed: ") + e.err);
    return 1;
  } catch (const Ort::Exception& e) {
    set_error(err, err_len, std::string("The neural model failed: ") + e.what());
    return 1;
  } catch (const std::exception& e) {
    set_error(err, err_len, std::string("Image processing failed: ") + e.what());
    return 1;
  }
}

}  // namespace

// Removes blur with a classical method.
//
// method: 0 sharpen, 1 out-of-focus deconvolution, 2 motion deconvolution.
// radius: Gaussian sigma (0), disk radius (1) or motion length (2), pixels.
// angle_deg: motion direction; ignored unless method is 2.
// strength: 0..100.
BLUR_EXPORT int blur_deblur(const char* input_path, const char* output_path,
                            int method, double radius, double angle_deg,
                            double strength, char* err, int err_len) {
  if (method < kSharpen || method > kMotion) {
    set_error(err, err_len, "Unknown deblur method");
    return 1;
  }
  if (!(radius > 0.0) || !(strength >= 0.0 && strength <= 100.0)) {
    set_error(err, err_len, "Deblur settings are out of range");
    return 1;
  }
  return process_file(input_path, output_path, err, err_len,
                      [&](const cv::Mat& work) {
                        switch (method) {
                          case kFocus:
                            return deconvolve(work, disk_psf(radius), strength);
                          case kMotion:
                            return deconvolve(
                                work, motion_psf(radius, angle_deg), strength);
                          default:
                            return sharpen(work, radius, strength);
                        }
                      });
}

// Removes blur with the neural model at `model_path` (contract: see
// neural_restore). Tries the GPU first and falls back to the CPU. On success
// `device` holds "gpu", or "cpu: <why the GPU was not used>".
BLUR_EXPORT int blur_neural_deblur(const char* input_path,
                                   const char* output_path,
                                   const char* model_path, char* device,
                                   int device_len, char* err, int err_len) {
  if (!std::ifstream(model_path).good()) {
    set_error(err, err_len, std::string("Cannot read model: ") + model_path);
    return 1;
  }
  return process_file(input_path, output_path, err, err_len,
                      [&](const cv::Mat& work) {
                        try {
                          cv::Mat result =
                              neural_restore(work, model_path, true);
                          set_error(device, device_len, "gpu");
                          return result;
                        } catch (const Ort::Exception& e) {
                          cv::Mat result =
                              neural_restore(work, model_path, false);
                          set_error(device, device_len,
                                    "cpu: " + gpu_failure_reason(e.what()));
                          return result;
                        }
                      });
}
