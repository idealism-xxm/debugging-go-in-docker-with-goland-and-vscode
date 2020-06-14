.PHONY: build-debug-base build-debug

build-debug-base:
	docker build -t debugging-go-in-docker-base:debug -f Dockerfile.debug.base .

build-debug:
	docker build -t debugging-go-in-docker:debug -f Dockerfile.debug .


.PHONY: debug

debug:
	# --build 每次都构建镜像， --force-recreate 每次都重新创建容器，方便快速重启新的调试
	docker-compose -f docker-compose-debug.yml up -d --build --force-recreate debugging-go-in-docker
