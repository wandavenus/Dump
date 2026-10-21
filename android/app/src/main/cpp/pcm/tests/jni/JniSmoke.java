import dev.wndavenz.music.audio.mixer.NativePcmBridge;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public final class JniSmoke {
    private static int checks = 0;
    private static int failures = 0;

    private static void check(boolean condition, String message) {
        checks++;
        if (!condition) {
            failures++;
            System.err.println("FAIL: " + message);
        }
    }

    private static void near(float actual, float expected, float tolerance, String message) {
        check(Math.abs(actual - expected) <= tolerance,
            message + " actual=" + actual + " expected=" + expected);
    }

    public static void main(String[] args) {
        // Converter: 48k bypass, S16 stereo, two frames stored at byte offset 4.
        long converter = NativePcmBridge.nativeCreateDeckConverter(48000, 48000);
        check(converter != 0L, "converter handle");
        check(NativePcmBridge.nativeDeckOutputFramesUpperBound(converter, 2) == 2,
            "bypass upper bound");

        ByteBuffer direct = ByteBuffer.allocateDirect(12).order(ByteOrder.nativeOrder());
        direct.position(0);
        direct.putInt(0x11223344); // padding before the payload
        direct.putShort((short) -32768);
        direct.putShort((short) 16384);
        direct.putShort((short) 32767);
        direct.putShort((short) -16384);
        direct.position(0);

        float[] output = new float[4];
        int produced = NativePcmBridge.nativeProcessDeck(
            converter, direct, 4, 2, 2, 1, false, output);
        check(produced == 2, "converter produced frames: " + produced);
        near(output[0], -1.0f, 1e-7f, "frame 0 left");
        near(output[1], 16384.0f / 32768.0f, 1e-7f, "frame 0 right");
        near(output[2], 32767.0f / 32768.0f, 1e-7f, "frame 1 left");
        near(output[3], -0.5f, 1e-7f, "frame 1 right");

        // A short output array must be rejected without advancing state.
        float[] tooShort = new float[2];
        int rejected = NativePcmBridge.nativeProcessDeck(
            converter, direct, 4, 2, 2, 1, false, tooShort);
        check(rejected < 0, "short output rejected: " + rejected);

        NativePcmBridge.nativeResetDeckConverter(converter);
        NativePcmBridge.nativeDestroyDeckConverter(converter);

        // Mixer: gains ramp, inactive deck is ignored, limiter caps the bus.
        long mixer = NativePcmBridge.nativeCreateMixer(48000, 8);
        check(mixer != 0L, "mixer handle");
        float[] deck0 = new float[16];
        float[] deck1 = new float[16];
        for (int i = 0; i < 16; i++) {
            deck0[i] = 1.0f;
            deck1[i] = 1.0f;
        }
        float[] gains = {0.0f, 0.25f};
        float[] targets = {1.0f, 1.0f};
        float[] mixed = new float[16];
        boolean ok = NativePcmBridge.nativeMix(
            mixer, 1, deck0, deck1, gains, targets, mixed, 8);
        check(ok, "nativeMix returned true");
        check(mixed[0] > 0.0f && mixed[0] < 0.01f, "first ramped sample: " + mixed[0]);
        near(gains[1], 0.25f, 1e-7f, "inactive gain unchanged");
        for (int i = 0; i < 16; i++) {
            check(Math.abs(mixed[i]) <= 0.98f + 1e-7f, "limiter ceiling at " + i);
        }

        // NaN must become silence without changing the release envelope.
        float[] nanDeck = {Float.NaN, Float.NaN, 0.5f, 0.5f};
        float[] freshGains = {1.0f, 1.0f};
        float[] nanOut = new float[4];
        check(NativePcmBridge.nativeMix(
            mixer, 1, nanDeck, null, freshGains, targets, nanOut, 2), "NaN block");
        near(nanOut[0], 0.0f, 1e-7f, "NaN left silenced");
        near(nanOut[1], 0.0f, 1e-7f, "NaN right silenced");
        near(nanOut[2], 0.5f, 1e-7f, "post-NaN sample untouched");

        float[] oversized = new float[20];
        check(!NativePcmBridge.nativeMix(
            mixer, 1, deck0, null, gains, targets, oversized, 9), "oversized block rejected");
        NativePcmBridge.nativeResetMixer(mixer);
        NativePcmBridge.nativeDestroyMixer(mixer);

        if (failures == 0) {
            System.out.println("PASS: " + checks + " JNI checks");
        } else {
            System.err.println("FAILED: " + failures + "/" + checks);
            System.exit(1);
        }
    }
}
