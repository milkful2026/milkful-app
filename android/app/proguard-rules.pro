# MA-125 FR-10: razorpay_flutter's checkout sheet uses reflection over the
# Razorpay Android SDK, which R8/ProGuard's default shrinking breaks unless
# these classes are kept. Not yet wired into build.gradle.kts's release
# buildType (minifyEnabled is off there today) — add
# `proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")`
# to that buildType if/when release shrinking is turned on.
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
