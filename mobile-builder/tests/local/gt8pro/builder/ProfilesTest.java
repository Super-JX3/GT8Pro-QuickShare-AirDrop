package local.gt8pro.builder;
import java.util.Arrays;
import java.util.Collections;
public final class ProfilesTest {
  public static void main(String[] args) {
    String model="RMX5200", fw="RMX5200_16.0.10.501(CN01)";
    if (!Profiles.matches(model,fw,36,Arrays.asList("arm64-v8a"))) throw new AssertionError("known profile rejected");
    if (Profiles.matches("other",fw,36,Arrays.asList("arm64-v8a"))
        || Profiles.matches(model,"other",36,Arrays.asList("arm64-v8a"))
        || Profiles.matches(model,fw,35,Arrays.asList("arm64-v8a"))
        || Profiles.matches(model,fw,36,Collections.singletonList("armeabi-v7a"))
        || Profiles.matches(model,fw,36,null)) throw new AssertionError("unknown profile accepted");
    System.out.println("PROFILE_GUARD=PASS");
  }
}
