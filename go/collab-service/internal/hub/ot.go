package hub

// transformLow transforms op (lower priority) against against.
// On equal-position insert/insert, op is shifted right (against wins).
// Returns nil if op becomes a no-op (concurrent delete on same position).
func transformLow(op, against *Op) *Op {
	return itransform(op, against, false)
}

// transformHigh transforms op (higher priority) against against.
// On equal-position insert/insert, op stays (op wins).
// Returns nil if op becomes a no-op.
func transformHigh(op, against *Op) *Op {
	return itransform(op, against, true)
}

// itransform is the Inclusion Transformation core.
// opWins controls tie-breaking on equal-position insert/insert.
func itransform(op, against *Op, opWins bool) *Op {
	if op == nil || against == nil {
		return op
	}
	result := *op

	switch {
	case op.Type == "insert" && against.Type == "insert":
		if op.Pos > against.Pos {
			result.Pos++
		} else if op.Pos == against.Pos && !opWins {
			result.Pos++
		}

	case op.Type == "insert" && against.Type == "delete":
		if op.Pos > against.Pos {
			result.Pos--
		}

	case op.Type == "delete" && against.Type == "insert":
		if op.Pos >= against.Pos {
			result.Pos++
		}

	case op.Type == "delete" && against.Type == "delete":
		if op.Pos > against.Pos {
			result.Pos--
		} else if op.Pos == against.Pos {
			return nil // position already deleted by concurrent op
		}
	}

	return &result
}

// transformSince transforms a client op against every server op from clientVersion onward.
// serverOps[i] is the op that produced server version i+1.
// The client op has lower priority (server ops win on tie).
func transformSince(op *Op, serverOps []Op, clientVersion int) *Op {
	for i := clientVersion; i < len(serverOps); i++ {
		against := serverOps[i]
		op = transformLow(op, &against)
		if op == nil {
			return nil
		}
	}
	return op
}

// apply returns content with op applied.
func apply(content string, op *Op) string {
	if op == nil {
		return content
	}
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
