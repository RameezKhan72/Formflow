  # FormFlow release (R8) keep rules.
  # Fixes: "Failed to create an instance of androidx.work.impl.WorkDatabase".
  -keep class * extends androidx.room.RoomDatabase { <init>(); }
  -keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }
  -keep class androidx.work.impl.** { *; }
  -keep class androidx.work.** { *; }
  -keepclassmembers class * extends androidx.work.ListenableWorker {
      public <init>(android.content.Context, androidx.work.WorkerParameters);
  }
  -dontwarn androidx.work.**