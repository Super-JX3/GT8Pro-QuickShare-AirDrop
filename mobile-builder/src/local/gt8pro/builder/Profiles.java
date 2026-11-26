package local.gt8pro.builder;

import java.util.List;

/** The generated GMS profile changes no part of the reviewed device configuration. */
final class Profiles {
    static boolean matches(String model, String firmware, int sdk, List<String> abis) {
        return "RMX5200".equals(model)
            && "RMX5200_16.0.10.501(CN01)".equals(firmware)
            && sdk == 36 && abis != null && abis.contains("arm64-v8a");
    }
}
