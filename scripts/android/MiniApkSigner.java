import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;
import java.io.File;
import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.zip.ZipFile;
import java.nio.ByteBuffer;
import com.android.apksig.apk.ApkUtils;

/**
 * Minimal `apksigner` replacement built on Google's apksig library (v1 + v2 + v3 schemes).
 * Implements the subset of the CLI Godot's Android exporter invokes:
 *   sign --ks <keystore> --ks-pass pass:<pw> --ks-key-alias <alias> [--key-pass pass:<pw>] [--min-sdk-version N] [--out <apk>] <apk>
 *   verify [--verbose] [--print-certs] <apk>
 * Unknown flags with values are ignored. Used only where the Android SDK build-tools are unavailable.
 */
public class MiniApkSigner {
    public static void main(String[] args) throws Exception {
        if (args.length == 0) { System.err.println("usage: sign|verify ..."); System.exit(2); }
        if (args[0].equals("--version") || args[0].equals("version")) { System.out.println("0.9 (MiniApkSigner on apksig 2.3.0)"); return; }
        String cmd = args[0];
        String ks = null, ksPass = null, alias = null, keyPass = null, out = null, apk = null;
        int minSdk = -1;
        for (int i = 1; i < args.length; i++) {
            String a = args[i];
            switch (a) {
                case "--ks": ks = args[++i]; break;
                case "--ks-pass": ksPass = strip(args[++i]); break;
                case "--key-pass": keyPass = strip(args[++i]); break;
                case "--ks-key-alias": alias = args[++i]; break;
                case "--out": out = args[++i]; break;
                case "--min-sdk-version": minSdk = Integer.parseInt(args[++i]); break;
                case "--verbose": case "--print-certs": case "-v": break;
                default:
                    if (a.startsWith("--")) { if (i + 1 < args.length && !args[i + 1].startsWith("--") && i + 1 != args.length - 1) i++; }
                    else apk = a;
            }
        }
        if (apk == null) { System.err.println("missing apk"); System.exit(2); }
        if (cmd.equals("verify")) {
            ApkVerifier.Result r = new ApkVerifier.Builder(new File(apk)).build().verify();
            System.out.println("Verified using v1 scheme (JAR signing): " + r.isVerifiedUsingV1Scheme());
            System.out.println("Verified using v2 scheme (APK Signature Scheme v2): " + r.isVerifiedUsingV2Scheme());
            if (!r.isVerified()) { r.getErrors().forEach(e -> System.err.println("ERROR: " + e)); System.exit(1); }
            System.out.println("Verifies");
            return;
        }
        if (!cmd.equals("sign")) { System.err.println("unknown command " + cmd); System.exit(2); }
        KeyStore store = KeyStore.getInstance(KeyStore.getDefaultType());
        try (FileInputStream in = new FileInputStream(ks)) { store.load(in, ksPass.toCharArray()); }
        if (alias == null) alias = Collections.list(store.aliases()).get(0);
        PrivateKey key = (PrivateKey) store.getKey(alias, (keyPass != null ? keyPass : ksPass).toCharArray());
        List<X509Certificate> certs = new ArrayList<>();
        for (Certificate c : store.getCertificateChain(alias)) certs.add((X509Certificate) c);
        ApkSigner.SignerConfig signer = new ApkSigner.SignerConfig.Builder("CERT", key, certs).build();
        File input = new File(apk);
        if (minSdk < 0) minSdk = manifestMinSdk(input);
        File tmp = File.createTempFile("signed", ".apk", input.getAbsoluteFile().getParentFile());
        new ApkSigner.Builder(List.of(signer))
            .setInputApk(input).setOutputApk(tmp).setMinSdkVersion(minSdk)
            .setV1SigningEnabled(true).setV2SigningEnabled(true).setV3SigningEnabled(true)
            .build().sign();
        File dest = out != null ? new File(out) : input;
        Files.move(tmp.toPath(), dest.toPath(), StandardCopyOption.REPLACE_EXISTING);
        System.out.println("Signed " + dest);
    }
    private static int manifestMinSdk(File apk) throws Exception {
        try (ZipFile z = new ZipFile(apk)) {
            byte[] m = z.getInputStream(z.getEntry("AndroidManifest.xml")).readAllBytes();
            return ApkUtils.getMinSdkVersionFromBinaryAndroidManifest(ByteBuffer.wrap(m));
        }
    }
    private static String strip(String p) { return p.startsWith("pass:") ? p.substring(5) : p; }
}
