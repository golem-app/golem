/// Deep-equality helpers for domain value objects. Pure Dart on purpose —
/// domain code must stay Flutter-free, so `package:flutter/foundation.dart`'s
/// versions are off limits here.
library;

bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

bool mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

int listHash<T>(List<T> list) => Object.hashAll(list);

int setHash<T>(Set<T> set) => Object.hashAllUnordered(set);

int mapHash<K, V>(Map<K, V> map) => Object.hashAllUnordered([
  for (final entry in map.entries) Object.hash(entry.key, entry.value),
]);
