package com.prepplanner.backend.topic;

import java.sql.Array;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class TopicRepository {

    /**
     * Topics in learning order: a topic's depth is the longest prerequisite chain above it,
     * so every prerequisite sorts before the topics that depend on it.
     * Assumes topic_prerequisites is acyclic (a cycle would make the recursive query loop).
     */
    private static final String LEARNING_ORDER_SQL = """
            WITH RECURSIVE walk AS (
                SELECT t.id, 0 AS d
                FROM topics t
                WHERE NOT EXISTS (SELECT 1 FROM topic_prerequisites p WHERE p.topic_id = t.id)
                UNION ALL
                SELECT tp.topic_id, walk.d + 1
                FROM topic_prerequisites tp
                JOIN walk ON tp.prerequisite_id = walk.id
            ),
            depths AS (
                SELECT id, max(d) AS depth FROM walk GROUP BY id
            )
            SELECT t.slug, t.name, t.track, d.depth,
                   ARRAY(SELECT p.slug
                         FROM topic_prerequisites tp
                         JOIN topics p ON p.id = tp.prerequisite_id
                         WHERE tp.topic_id = t.id
                         ORDER BY p.slug) AS prerequisites
            FROM topics t
            JOIN depths d ON d.id = t.id
            ORDER BY d.depth, t.track, t.slug
            """;

    private final JdbcClient jdbc;

    public TopicRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public List<Topic> findAllInLearningOrder() {
        return jdbc.sql(LEARNING_ORDER_SQL)
                .query((rs, rowNum) -> new Topic(
                        rs.getString("slug"),
                        rs.getString("name"),
                        rs.getString("track"),
                        rs.getInt("depth"),
                        toList(rs.getArray("prerequisites"))))
                .list();
    }

    private static List<String> toList(Array array) throws SQLException {
        if (array == null) {
            return List.of();
        }
        return Arrays.asList((String[]) array.getArray());
    }
}
