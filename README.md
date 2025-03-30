# mora

mora is a tool for orchestrating a homelab built on k8s. i need k8s because it
properly does all of the things i want for my homelab like service discovery,
auto-healing, horizontal scaling, etc. but k8s is an absolute pain to deal with,
so mora is a tool to make it so i don't need to deal with k8s directly. instead,
i can configure my homelab in a nice little directory structure and mora will
handle creating the k8s manifests and setting everything up and all that.
