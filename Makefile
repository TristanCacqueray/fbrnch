stack-all:
	stack --resolver nightly --stack-yaml stack-lts15.yaml build
	@echo
	stack --resolver lts-15 --stack-yaml stack-lts15.yaml build
	@echo
	stack --resolver lts-14 build
	@echo
	stack --resolver lts-13 --stack-yaml stack-lts13.yaml build
	@echo
	stack --resolver lts-12 --stack-yaml stack-lts12.yaml build
	@echo
	stack --resolver lts-11 --stack-yaml stack-lts12.yaml build
#	@echo
#	@echo bugzilla fails: setRequestCheckStatus
#	stack --resolver lts-10 --stack-yaml stack-lts10.yaml build
