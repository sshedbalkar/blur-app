// Native image engine for Blur App. Called from Dart through FFI
// (lib/features/deblur/deblur_native.dart). Keep the exported signatures in
// sync with that file.

#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

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

}  // namespace

// Reads `input_path`, removes blur, writes `output_path` (format chosen by
// its extension). Returns 0 on success; otherwise non-zero with a message in
// `err`.
//
// method: 0 sharpen, 1 out-of-focus deconvolution, 2 motion deconvolution.
// radius: Gaussian sigma (0), disk radius (1) or motion length (2), pixels.
// angle_deg: motion direction; ignored unless method is 2.
// strength: 0..100.
BLUR_EXPORT int blur_deblur(const char* input_path, const char* output_path,
                            int method, double radius, double angle_deg,
                            double strength, char* err, int err_len) {
  try {
    if (method < kSharpen || method > kMotion) {
      set_error(err, err_len, "Unknown deblur method");
      return 1;
    }
    if (!(radius > 0.0) || !(strength >= 0.0 && strength <= 100.0)) {
      set_error(err, err_len, "Deblur settings are out of range");
      return 1;
    }

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

    cv::Mat result;
    switch (method) {
      case kSharpen:
        result = sharpen(work, radius, strength);
        break;
      case kFocus:
        result = deconvolve(work, disk_psf(radius), strength);
        break;
      case kMotion:
        result = deconvolve(work, motion_psf(radius, angle_deg), strength);
        break;
    }

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
  } catch (const std::exception& e) {
    set_error(err, err_len, std::string("Image processing failed: ") + e.what());
    return 1;
  }
}
