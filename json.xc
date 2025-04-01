#include <json.xh>

size_t showJsonMaxLen(Json j) {
  return match (j) (
    JsonNull() -> 4;
    JsonBool(_) -> 5;
    JsonInteger(_) -> MAX_LONG_STR_LEN;
    JsonNumber(_) -> MAX_DOUBLE_STR_LEN;
    JsonString(s) -> show_string_max_len(s);
    JsonArray(a) -> ({
      size_t result = 2;
      if (a.size > 0) {
        result += showJsonMaxLen(a[0]);
      }
      for (size_t i = 1; i < a.size; i++) {
        result += 2 + showJsonMaxLen(a[i]);
      }
      result;
    });
    JsonObject(o) -> ({
      size_t result = 2;
      if (o.size > 0) {
        result += show_string_max_len(o[0].key) + 2 + showJsonMaxLen(o[0].value);
      }
      for (size_t i = 1; i < o.size; i++) {
        result += 2 + show_string_max_len(o[i].key) + 2 + showJsonMaxLen(o[i].value);
      }
      result;
    });
  );
}

size_t showJson(char buf[], Json j) {
  return match (j) (
    JsonNull() -> sprintf(buf, "null");
    JsonBool(b) -> sprintf(buf, b ? "true" : "false");
    JsonInteger(i) -> sprintf(buf, "%ld", i);
    JsonNumber(f) -> sprintf(buf, "%f", f);
    JsonString(s) -> showToBuf(buf, s);
    JsonArray(a) -> ({
      buf[0] = '[';
      size_t bufIndex = 1;
      if (a.size > 0) {
        bufIndex += showJson(buf + bufIndex, a[0]);
      }
      for (size_t i = 1; i < a.size; i++) {
        buf[bufIndex++] = ',';
        buf[bufIndex++] = ' ';
        bufIndex += showJson(buf + bufIndex, a[i]);
      }
      buf[bufIndex++] = ']';
      buf[bufIndex] = '\0';
      bufIndex;
    });
    JsonObject(o) -> ({
      buf[0] = '{';
      size_t bufIndex = 1;
      if (o.size > 0) {
        bufIndex += showToBuf(buf + bufIndex, o[0].key);
        buf[bufIndex++] = ':';
        buf[bufIndex++] = ' ';
        bufIndex += showJson(buf + bufIndex, o[0].value);
      }
      for (size_t i = 1; i < o.size; i++) {
        buf[bufIndex++] = ',';
        buf[bufIndex++] = ' ';
        bufIndex += showToBuf(buf + bufIndex, o[i].key);
        buf[bufIndex++] = ':';
        buf[bufIndex++] = ' ';
        bufIndex += showJson(buf + bufIndex, o[i].value);
      }
      buf[bufIndex++] = '}';
      buf[bufIndex] = '\0';
      bufIndex;
    });
  );
}
