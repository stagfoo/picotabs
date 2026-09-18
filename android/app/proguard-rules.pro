# R8 rules for the release build.
#
# The Flutter Gradle plugin contributes the rules the engine and the embedding
# need, so this file only has to cover what belongs to this app.

# MainActivity is named in AndroidManifest.xml, so R8 keeps it on its own. Named
# here anyway because everything the launcher can do goes through it: if it were
# ever renamed or reached only reflectively, the failure would be a launcher
# that installs and then does nothing.
-keep class com.mindmesh.mindmesh.MainActivity { *; }

# Method-channel handlers are invoked from the platform side by name.
-keepclassmembers class com.mindmesh.mindmesh.** {
    public *** *(...);
}
