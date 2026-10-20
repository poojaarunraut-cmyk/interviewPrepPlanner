package com.prepplanner.backend;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.simple.JdbcClient;

import com.prepplanner.backend.topic.Topic;
import com.prepplanner.backend.topic.TopicRepository;

/** Runs the real Flyway migrations against PostgreSQL in a Testcontainers container. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(TestcontainersConfiguration.class)
class SchemaAndTopicsTests {

    @Autowired
    JdbcClient jdbc;

    @Autowired
    TopicRepository topicRepository;

    @Value("${local.server.port}")
    int port;

    private final HttpClient http = HttpClient.newHttpClient();

    @Test
    void migrationsSeedAllTopics() {
        Long count = jdbc.sql("SELECT count(*) FROM topics").query(Long.class).single();
        assertThat(count).isEqualTo(20L);
    }

    @Test
    void everyPrerequisiteComesBeforeTheTopicThatNeedsIt() {
        List<Topic> topics = topicRepository.findAllInLearningOrder();
        Map<String, Integer> position = new HashMap<>();
        for (int i = 0; i < topics.size(); i++) {
            position.put(topics.get(i).slug(), i);
        }
        for (Topic topic : topics) {
            for (String prerequisite : topic.prerequisites()) {
                assertThat(position.get(prerequisite))
                        .as("%s must come before %s", prerequisite, topic.slug())
                        .isLessThan(position.get(topic.slug()));
            }
        }
    }

    @Test
    void reimportingTheSameVideoIsRejected() {
        Long sourceId = jdbc.sql("""
                INSERT INTO sources (kind, external_ref) VALUES ('youtube_playlist', 'test-playlist-dup')
                RETURNING id""").query(Long.class).single();
        String insertResource = """
                INSERT INTO resources (source_id, external_id, type, url, title)
                VALUES (:sourceId, 'video-1', 'video', 'https://www.youtube.com/watch?v=video-1', 'Two Sum')""";

        jdbc.sql(insertResource).param("sourceId", sourceId).update();

        assertThatThrownBy(() -> jdbc.sql(insertResource).param("sourceId", sourceId).update())
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void topicsEndpointReturnsTopicsInLearningOrder() throws Exception {
        HttpResponse<String> response = get("/api/topics");
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).contains("\"slug\":\"arrays\"");
        assertThat(response.body().indexOf("\"slug\":\"trees\""))
                .isLessThan(response.body().indexOf("\"slug\":\"graphs\""));
    }

    @Test
    void healthEndpointIsUp() throws Exception {
        HttpResponse<String> response = get("/actuator/health");
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).contains("UP");
    }

    private HttpResponse<String> get(String path) throws Exception {
        HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path)).build();
        return http.send(request, HttpResponse.BodyHandlers.ofString());
    }
}
