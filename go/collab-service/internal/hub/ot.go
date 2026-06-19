package hub

// transform adjusts op assuming it was created against a document
// that is `delta` versions behind the current server version.
// This is a simplified positional transform (no buffered op history).
// A full OT engine would store all server ops and compose transforms.
func transform(op *Op, delta int) *Op {
	if delta <= 0 || op == nil {
		return op
	}
	// Without the actual intervening ops we can't do precise transforms.
	// We return the op as-is; the server is the authority on ordering.
	// TODO: buffer server ops and apply proper IT/ET transforms.
	result := *op
	return &result
}

// apply mutates content by applying op and returns the new string.
func apply(content string, op *Op) string {
	runes := []rune(content)
	pos := clamp(op.Pos, 0, len(runes))

	switch op.Type {
	case "insert":
		if op.Char == "" {
			return content
		}
		ch := []rune(op.Char)[0]
		out := make([]rune, len(runes)+1)
		copy(out, runes[:pos])
		out[pos] = ch
		copy(out[pos+1:], runes[pos:])
		return string(out)

	case "delete":
		if pos >= len(runes) {
			return content
		}
		out := make([]rune, len(runes)-1)
		copy(out, runes[:pos])
		copy(out[pos:], runes[pos+1:])
		return string(out)
	}

	return content
}

func clamp(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}
