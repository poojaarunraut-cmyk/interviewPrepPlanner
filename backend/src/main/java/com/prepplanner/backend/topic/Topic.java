package com.prepplanner.backend.topic;

import java.util.List;

/** A study topic, with its depth in the prerequisite graph (0 = no prerequisites). */
public record Topic(String slug, String name, String track, int depth, List<String> prerequisites) {
}
