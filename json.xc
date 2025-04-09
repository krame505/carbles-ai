#include <json.xh>
#include <stdbool.h>

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

static inline void skipWhitespace(string s, size_t *i) {
  while (s[*i] == ' ' || s[*i] == '\n' || s[*i] == '\r' || s[*i] == '\t') {
    (*i)++;
  }
}

static Result<string> parseStringAt(string s, size_t *i, arena_t ar) {
  allocate_using arena ar;
  if (s[*i] != '"') {
    return Err<string>("expected '\"' at index " + str(*i));
  }
  (*i)++;
  size_t len = 0;
  size_t j = *i;
  while (s[j] != '"' && s[j] != '\0') {
    if (s[j] == '\\') j++;
    j++; len++;
  }
  char unescaped[len + 1];
  j = 0;
  while (s[*i] != '"') {
    if (s[*i] == '\0') {
      return Err<string>("unterminated string at index " + str(*i));
    } else if (s[*i] == '\\') {
      (*i)++;
      // TODO: handle hex and unicode escapes
      switch (s[*i]) {
      case 'n':
        unescaped[j] = '\n';
        break;
      case 'r':
        unescaped[j] = '\r';
        break;
      case 't':
        unescaped[j] = '\t';
        break;
      case 'v':
        unescaped[j] = '\v';
        break;
      case '\"':
      case '\\':
      case '?':
        unescaped[j] = s[*i];
        break;
      default:
        return Err<string>("unexpected escape sequence at index " + str(*i));
      }
    } else {
      unescaped[j] = s[*i];
    }
    j++; (*i)++;
  }
  unescaped[j] = '\0';
  (*i)++;
  return Ok(str(unescaped));
}

// TODO: could use a regex extension here...
static Result<Json> parseJsonAt(string s, size_t *i, arena_t ar) {
  allocate_using arena ar;
  long l; double d; int n; // for sscanf
  skipWhitespace(s, i);
  if (!strncmp(s.text + *i, "null", 4)) {
    *i += 4;
    return Ok(JsonNull());
  } else if (!strncmp(s.text + *i, "true", 4)) {
    *i += 4;
    return Ok(JsonBool(true));
  } else if (!strncmp(s.text + *i, "false", 5)) {
    *i += 5;
    return Ok(JsonBool(false));
  } else if (s[*i] == '"') {
    match (parseStringAt(s, i, ar)) {
      Ok(s) -> { return Ok(JsonString(s)); }
      Err(msg) -> { return Err<Json>(msg); }
    }
  } else if (s[*i] == '[') {
    (*i)++;
    vector<Json> items = {};
    while (s[*i] != ']') {
      match (parseJsonAt(s, i, ar)) {
        Ok(item) -> { items.append(item); }
        Err(msg) -> { return Err<Json>(msg); }
      }
      skipWhitespace(s, i);
      if (s[*i] == ',') {
        (*i)++;
      } else if (s[*i] != ']') {
        return Err<Json>("expected ',' or ']' at index " + str(*i));
      }
    }
    (*i)++;
    return Ok(JsonArray(items));
  } else if (s[*i] == '{') {
    (*i)++;
    vector<JsonItem> items = {};
    while (s[*i] != '}') {
      skipWhitespace(s, i);
      string key;
      match (parseStringAt(s, i, ar)) {
        Ok(k) -> { key = k; }
        Err(msg) -> { return Err<Json>(msg); }
      }
      skipWhitespace(s, i);
      if (s[*i] != ':') {
        return Err<Json>("expected ':' at index " + str(*i));
      }
      (*i)++;
      match (parseJsonAt(s, i, ar)) {
        Ok(value) -> { items.append((JsonItem){key, value}); }
        Err(msg) -> { return Err<Json>(msg); }
      }
      skipWhitespace(s, i);
      if (s[*i] == ',') {
        (*i)++;
      } else if (s[*i] != '}') {
        return Err<Json>("expected ',' or '}' at index " + str(*i));
      }
    }
    (*i)++;
    return Ok(JsonObject(items));
  } else if (sscanf(s.text + *i, "%ld%n", &l, &n)) {
    *i += n;
    return Ok(JsonInteger(l));
  } else if (sscanf(s.text + *i, "%lf%n", &d, &n)) {
    *i += n;
    return Ok(JsonNumber(n));
  } else {
    return Err<Json>("unexpected character at index " + str(*i));
  }
}

Result<Json> parseJson(string s, arena_t ar) {
  allocate_using arena ar;
  size_t i = 0;
  Result<Json> result = parseJsonAt(s, &i, ar);
  if (!isErr(result) && i < s.length) {
    return Err<Json>("trailing characters at index " + str(i));
  }
  return result;
}

Json getJsonField(Json j, string key) {
  match (j) {
    JsonObject(items) -> {
      for (size_t i = 0; i < items.size; i++) {
        if (items[i].key == key) {
          return items[i].value;
        }
      }
      return JsonNull();
    }
    _ -> { return JsonNull(); }
  }
}
