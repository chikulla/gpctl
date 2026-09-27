.PHONY: check

check:
	zsh -n gpctl
	zsh test/gpctl_test.zsh
