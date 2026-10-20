-- V2: DSA topics and their prerequisite DAG (edit freely; the planner orders topics topologically)
INSERT INTO topics (slug, name) VALUES
  ('arrays', 'Arrays'), ('hashing', 'Hashing'), ('two-pointers', 'Two pointers'),
  ('sliding-window', 'Sliding window'), ('binary-search', 'Binary search'),
  ('recursion', 'Recursion'), ('linked-list', 'Linked list'), ('stack-queue', 'Stack and queue'),
  ('trees', 'Trees'), ('heaps', 'Heaps'), ('tries', 'Tries'), ('graphs', 'Graphs'),
  ('backtracking', 'Backtracking'), ('greedy', 'Greedy'), ('dp', 'Dynamic programming');

INSERT INTO topic_prerequisites (topic_id, prerequisite_id)
SELECT t.id, p.id
FROM (VALUES
  ('hashing', 'arrays'), ('two-pointers', 'arrays'), ('sliding-window', 'two-pointers'),
  ('binary-search', 'arrays'), ('linked-list', 'arrays'), ('stack-queue', 'arrays'),
  ('trees', 'recursion'), ('heaps', 'trees'), ('tries', 'trees'), ('graphs', 'trees'),
  ('backtracking', 'recursion'), ('greedy', 'arrays'), ('dp', 'recursion')
) AS e(topic, prereq)
JOIN topics t ON t.slug = e.topic
JOIN topics p ON p.slug = e.prereq;

INSERT INTO topics (slug, name, track) VALUES
  ('lld-basics', 'OOP, SOLID and design patterns', 'lld'),
  ('lld-machine-coding', 'Machine coding problems', 'lld'),
  ('hld-fundamentals', 'Caching, sharding, queues, consistency', 'hld'),
  ('hld-case-studies', 'System design case studies', 'hld'),
  ('behavioral-star', 'STAR stories', 'behavioral');
INSERT INTO topic_prerequisites (topic_id, prerequisite_id)
SELECT t.id, p.id FROM topics t, topics p
WHERE (t.slug, p.slug) IN (('lld-machine-coding', 'lld-basics'), ('hld-case-studies', 'hld-fundamentals'));
