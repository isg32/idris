package com.isg32.idris;

import com.grack.nanojson.JsonObject;
import com.grack.nanojson.JsonParser;
import com.grack.nanojson.JsonWriter;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.schabi.newpipe.extractor.NewPipe;
import org.schabi.newpipe.extractor.ServiceList;
import org.schabi.newpipe.extractor.downloader.Downloader;
import org.schabi.newpipe.extractor.downloader.Request;
import org.schabi.newpipe.extractor.downloader.Response;
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException;
import org.schabi.newpipe.extractor.stream.AudioStream;
import org.schabi.newpipe.extractor.stream.DeliveryMethod;
import org.schabi.newpipe.extractor.stream.StreamInfo;

/**
 * Finds YouTube audio streams for Idris on Linux, as YouTubeChannel.kt does
 * on Android. Reads one JSON request per line on stdin:
 *
 * <pre>{"n": 1, "link": "https://www.youtube.com/watch?v=…", "quality": "best"}</pre>
 *
 * and answers on stdout, one line each, in any order:
 *
 * <pre>{"n": 1, "url": "…", "mime": "audio/webm", "bitrate": 160, "ms": 215000}</pre>
 *
 * or {@code {"n": 1, "error": "…"}}. It runs until stdin closes.
 */
public final class Extractor {
    private static final String USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0";

    /** Headers java.net.http sets itself and refuses from callers. */
    private static final Set<String> RESTRICTED =
        Set.of("host", "connection", "content-length", "expect", "upgrade");

    private static final HttpClient CLIENT = HttpClient.newBuilder()
        .followRedirects(HttpClient.Redirect.NORMAL)
        .connectTimeout(Duration.ofSeconds(15))
        .build();

    public static void main(String[] args) throws IOException {
        NewPipe.init(new HttpDownloader());
        PrintStream out = new PrintStream(System.out, true, StandardCharsets.UTF_8);
        ExecutorService pool = Executors.newFixedThreadPool(4);
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while ((line = in.readLine()) != null) {
            if (line.isBlank()) continue;
            final String request = line;
            pool.execute(() -> {
                String reply = answer(request);
                synchronized (out) {
                    out.println(reply);
                }
            });
        }
        pool.shutdown();
    }

    private static String answer(String line) {
        long n = -1;
        try {
            JsonObject req = JsonParser.object().from(line);
            n = req.getLong("n", -1);
            StreamInfo info = StreamInfo.getInfo(ServiceList.YouTube, req.getString("link"));
            List<AudioStream> streams = info.getAudioStreams().stream()
                .filter(s -> s.getDeliveryMethod() == DeliveryMethod.PROGRESSIVE_HTTP && s.isUrl())
                .toList();
            AudioStream s = pick(streams, req.getString("quality", "best"));
            if (s == null) throw new IllegalStateException("No playable audio stream");
            return JsonWriter.string()
                .object()
                .value("n", n)
                .value("url", s.getContent())
                .value("mime", s.getFormat() == null ? null : s.getFormat().getMimeType())
                .value("bitrate", s.getAverageBitrate())
                .value("ms", info.getDuration() * 1000)
                .end()
                .done();
        } catch (Exception e) {
            String message = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            return JsonWriter.string().object().value("n", n).value("error", message).end().done();
        }
    }

    /** The same choice as YouTubeChannel.kt's: by quality, m4a first on a tie. */
    private static AudioStream pick(List<AudioStream> streams, String quality) {
        if (streams.isEmpty()) return null;
        Comparator<AudioStream> m4aFirst = Comparator.comparing(
            (AudioStream s) -> s.getFormat() != null && "audio/mp4".equals(s.getFormat().getMimeType()))
            .reversed();
        Comparator<AudioStream> order = switch (quality) {
            case "low" -> Comparator.comparingInt(AudioStream::getAverageBitrate).thenComparing(m4aFirst);
            case "high", "medium" -> {
                int target = quality.equals("high") ? 160 : 128;
                yield Comparator.comparingInt((AudioStream s) -> Math.abs(s.getAverageBitrate() - target))
                    .thenComparing(m4aFirst);
            }
            default -> Comparator.comparingInt(AudioStream::getAverageBitrate).reversed().thenComparing(m4aFirst);
        };
        return streams.stream().sorted(order).findFirst().orElse(null);
    }

    private static final class HttpDownloader extends Downloader {
        @Override
        public Response execute(Request request) throws IOException, ReCaptchaException {
            HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(request.url()))
                .timeout(Duration.ofSeconds(30))
                .header("User-Agent", USER_AGENT);
            for (Map.Entry<String, List<String>> h : request.headers().entrySet()) {
                if (RESTRICTED.contains(h.getKey().toLowerCase())) continue;
                for (String v : h.getValue()) b.header(h.getKey(), v);
            }
            byte[] body = request.dataToSend();
            b.method(request.httpMethod(),
                body == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofByteArray(body));
            try {
                HttpResponse<String> res = CLIENT.send(b.build(), HttpResponse.BodyHandlers.ofString());
                if (res.statusCode() == 429) {
                    throw new ReCaptchaException("reCaptcha challenge requested", request.url());
                }
                return new Response(res.statusCode(), "", res.headers().map(), res.body(), res.uri().toString());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IOException(e);
            }
        }
    }
}
