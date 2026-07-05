// FreeStyle Libre 3 crypto bridge — a dlopen shim to Abbott's proprietary
// `liblibre3extension.so`, ported from Juggluco's GPL
// `Common/src/main/cpp/libre3/loadlibs.cpp` (j-kaltes/Juggluco).
//
// Abbott's library registers its two crypto entry points (`process1`,
// `process2`) via JNI `RegisterNatives` inside its `JNI_OnLoad`. We can't link
// them directly, so — exactly as Juggluco does — we `dlopen` the library, call
// its `JNI_OnLoad` with a FAKE JavaVM whose `RegisterNatives` we intercept, and
// capture the two function pointers from the methods table.
//
// The Abbott `.so` is NOT in this repo (see jniLibs/README.md). Until it is
// present the `dlopen` fails, `ensureLoaded()` returns false, and every exported
// function returns a benign default so the Kotlin plugin reports `no_blob`.

#include <jni.h>
#include <dlfcn.h>
#include <cstring>
#include <string>
#include <android/log.h>

#define LOG_TAG "Libre3Bridge"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// Abbott's two crypto primitives, captured from its RegisterNatives call.
using Process1 = jint (*)(JNIEnv *, jclass, jint, jbyteArray, jbyteArray);
using Process2 = jbyteArray (*)(JNIEnv *, jclass, jint, jbyteArray, jbyteArray);

Process1 gProcess1 = nullptr;
Process2 gProcess2 = nullptr;
bool gTriedLoad = false;

// The class name whose native methods carry process1/process2.
const char *kCryptoClass =
    "com/adc/trident/app/frameworks/mobileservices/libre3/security/"
    "Libre3SKBCryptoLib";

// --- fake JNIEnv / JavaVM used only to intercept RegisterNatives ------------
// FindClass returns the name string itself as the jclass so RegisterNatives can
// strcmp it (Juggluco's trick); RegisterNatives grabs methods[0]/[1].

jclass fakeFindClass(JNIEnv *, const char *name) {
  return reinterpret_cast<jclass>(const_cast<char *>(strdup(name)));
}

jint fakeRegisterNatives(JNIEnv *, jclass clazz, const JNINativeMethod *methods,
                         jint count) {
  const char *name = reinterpret_cast<const char *>(clazz);
  if (name && strcmp(name, kCryptoClass) == 0 && count >= 2) {
    gProcess1 = reinterpret_cast<Process1>(methods[0].fnPtr);
    gProcess2 = reinterpret_cast<Process2>(methods[1].fnPtr);
  }
  return 0;
}

// In C++ JNIEnv/JavaVM are the `_JNIEnv`/`_JavaVM` wrapper structs, each holding
// a pointer to the actual interface table. Build both so Abbott's JNI_OnLoad
// sees a valid (but hooked) environment.
struct FakeContext {
  JNINativeInterface env{};
  JNIInvokeInterface vm{};
  _JNIEnv envObj{};
  _JavaVM vmObj{};
};

FakeContext gFake;

jint fakeGetEnv(JavaVM *, void **env, jint) {
  *env = &gFake.envObj;
  return JNI_OK;
}

jint fakeAttach(JavaVM *, JNIEnv **env, void *) {
  *env = &gFake.envObj;
  return JNI_OK;
}

// Load the Abbott library once and capture process1/process2. Returns true when
// both are available.
bool ensureLoaded() {
  if (gTriedLoad) {
    return gProcess1 && gProcess2;
  }
  gTriedLoad = true;

  void *handle = dlopen("liblibre3extension.so", RTLD_NOW);
  if (!handle) {
    LOGE("dlopen liblibre3extension.so failed: %s", dlerror());
    return false;
  }
  using OnLoad = jint (*)(JavaVM *, void *);
  auto onLoad = reinterpret_cast<OnLoad>(dlsym(handle, "JNI_OnLoad"));
  if (!onLoad) {
    LOGE("dlsym JNI_OnLoad failed: %s", dlerror());
    return false;
  }

  gFake.env.FindClass = fakeFindClass;
  gFake.env.RegisterNatives = fakeRegisterNatives;
  gFake.vm.GetEnv = fakeGetEnv;
  gFake.vm.AttachCurrentThread = fakeAttach;
  gFake.envObj.functions = &gFake.env;
  gFake.vmObj.functions = &gFake.vm;

  onLoad(&gFake.vmObj, nullptr);
  return gProcess1 && gProcess2;
}

}  // namespace

extern "C" {

JNIEXPORT jint JNICALL
Java_de_lukasbreuer_insulink_Libre3SecurityPlugin_processInt(
    JNIEnv *env, jclass clazz, jint command, jbyteArray a, jbyteArray b) {
  if (!ensureLoaded()) {
    return -1;
  }
  return gProcess1(env, clazz, command, a, b);
}

JNIEXPORT jbyteArray JNICALL
Java_de_lukasbreuer_insulink_Libre3SecurityPlugin_processBar(
    JNIEnv *env, jclass clazz, jint command, jbyteArray nonce, jbyteArray data) {
  if (!ensureLoaded()) {
    return nullptr;
  }
  return gProcess2(env, clazz, command, nonce, data);
}

}  // extern "C"
