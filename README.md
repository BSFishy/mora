# mora preflight

> [!NOTE]
> this project is pretty much sunset. i have learned what i needed to learn from
> it and now moving onto a different architecture. just using helm and deploying
> in phases.
>
> the main learning was k8s manifests and playing around with language design
> and implementation. i got what i wanted and continuing to maintain this would
> be a lot of effort for the same benefit of what i'll get with the new system.

mora preflight is the cli tool for mora. it will read in your configuration,
validate that it is valid, then send it to mora runway. mora runway is the piece
that does most of the work tbh
