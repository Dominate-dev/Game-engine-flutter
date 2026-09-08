// Bell (round 3) is client-derived, not server-sent — there is no phase
// field to decode on restore, unlike Auction. It follows directly from
// `GameSessionState.bellArmed` and the shared `currentTurn`: an assigned
// turn always means `answering`, regardless of `bellArmed`.
enum BellPhase { idle, racing, answering }
