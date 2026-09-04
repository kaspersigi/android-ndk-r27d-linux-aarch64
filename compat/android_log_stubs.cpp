#include <android/log.h>

#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <string>

namespace {

std::atomic<int32_t> minimum_priority{ANDROID_LOG_DEFAULT};
std::string default_tag;
std::mutex default_tag_mutex;
std::atomic<__android_logger_function> logger{__android_log_stderr_logger};
std::atomic<__android_aborter_function> aborter{__android_log_default_aborter};

int PrintFormatted(int buffer_id, int priority, const char* tag, const char* format, va_list args) {
  char buffer[4096];
  int result = vsnprintf(buffer, sizeof(buffer), format, args);
  __android_log_message message = {sizeof(message), buffer_id, priority, tag, nullptr, 0, buffer};
  __android_log_write_log_message(&message);
  return result;
}

}  // namespace

extern "C" {

int __android_log_write(int priority, const char* tag, const char* text) {
  __android_log_message message = {sizeof(message), LOG_ID_DEFAULT, priority, tag, nullptr, 0,
                                   text};
  __android_log_write_log_message(&message);
  return 1;
}

int __android_log_print(int priority, const char* tag, const char* format, ...) {
  va_list args;
  va_start(args, format);
  int result = PrintFormatted(LOG_ID_DEFAULT, priority, tag, format, args);
  va_end(args);
  return result;
}

int __android_log_vprint(int priority, const char* tag, const char* format, va_list args) {
  return PrintFormatted(LOG_ID_DEFAULT, priority, tag, format, args);
}

void __android_log_assert(const char* condition, const char* tag, const char* format, ...) {
  if (format != nullptr) {
    va_list args;
    va_start(args, format);
    PrintFormatted(LOG_ID_CRASH, ANDROID_LOG_FATAL, tag, format, args);
    va_end(args);
  } else {
    __android_log_print(ANDROID_LOG_FATAL, tag, "Assertion failed: %s",
                        condition != nullptr ? condition : "unknown condition");
  }
  __android_log_call_aborter(condition != nullptr ? condition : "assertion failed");
  abort();
}

int __android_log_buf_write(int buffer_id, int priority, const char* tag, const char* text) {
  __android_log_message message = {sizeof(message), buffer_id, priority, tag, nullptr, 0, text};
  __android_log_write_log_message(&message);
  return 1;
}

int __android_log_buf_print(int buffer_id, int priority, const char* tag, const char* format, ...) {
  va_list args;
  va_start(args, format);
  int result = PrintFormatted(buffer_id, priority, tag, format, args);
  va_end(args);
  return result;
}

void __android_log_write_log_message(__android_log_message* message) {
  logger.load(std::memory_order_acquire)(message);
}

void __android_log_set_logger(__android_logger_function new_logger) {
  logger.store(new_logger != nullptr ? new_logger : __android_log_stderr_logger,
               std::memory_order_release);
}

void __android_log_logd_logger(const __android_log_message* message) {
  __android_log_stderr_logger(message);
}

void __android_log_stderr_logger(const __android_log_message* message) {
  std::string tag_snapshot;
  if (message->tag == nullptr) {
    std::lock_guard<std::mutex> lock(default_tag_mutex);
    tag_snapshot = default_tag.empty() ? "simpleperf" : default_tag;
  }
  const char* tag = message->tag != nullptr ? message->tag : tag_snapshot.c_str();
  fprintf(stderr, "%s: %s\n", tag, message->message != nullptr ? message->message : "");
}

void __android_log_set_aborter(__android_aborter_function new_aborter) {
  aborter.store(new_aborter != nullptr ? new_aborter : __android_log_default_aborter,
                std::memory_order_release);
}

void __android_log_call_aborter(const char* message) {
  aborter.load(std::memory_order_acquire)(message);
}

void __android_log_default_aborter(const char*) {
  abort();
}

int __android_log_is_loggable(int priority, const char*, int default_priority) {
  int threshold = minimum_priority.load();
  if (threshold == ANDROID_LOG_DEFAULT) threshold = default_priority;
  return priority >= threshold;
}

int __android_log_is_loggable_len(int priority, const char*, size_t, int default_priority) {
  return __android_log_is_loggable(priority, nullptr, default_priority);
}

int32_t __android_log_set_minimum_priority(int32_t priority) {
  return minimum_priority.exchange(priority);
}

int32_t __android_log_get_minimum_priority() {
  return minimum_priority.load();
}

void __android_log_set_default_tag(const char* tag) {
  std::lock_guard<std::mutex> lock(default_tag_mutex);
  default_tag = tag != nullptr ? tag : "";
}

}  // extern "C"
