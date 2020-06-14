##### 背景

[go-face-recognition-comparison](https://github.com/idealism-xxm/go-face-recognition-comparison) 中介绍了 Go 中进行人脸识别的几个方法，并在 Docker 中进行了简单演示。那时的主要想法就是把示例写出来，还没想到要进行调试，但是已经体验到开发效率与本地运行时相差甚远。因为无法调试，只能从 `debug` 党转变为 `print` 党，每次修改示例后都要在相应的地方添加 `print` 方法打印所需要的信息，完成后还需要删除对应的 `print` 方法，这样不仅费时费力，还经常容易忘记删除 `print` 。

在实际开发时， `print` 方式的劣势就更为明显，因为一个请求涉及的代码链路很长，需要实时追踪，不可能到处写下 `print` ；并且有时还需要到引用的库内部查看一些变量的信息，就更不可能使用 `print` 方式。

##### 准备

实际开发中，我们所调试的 Go 应用都包含很多依赖库，这里我们使用一个简单的随机数的库进行模拟，使用以下 `go.mod` 文件：

```mod
module debugging-go-in-docker

go 1.14

require (
	github.com/NebulousLabs/fastrand v0.0.0-20181203155948-6fb6489aac4e // indirect
	golang.org/x/crypto v0.0.0-20200604202706-70a84ac30bf9 // indirect
)
```

接下来就是准备调试用的 Go 代码了，为了简单起见，我们仅做一些简单的操作，输出一些字符串，使用一下 `main.go` 文件：

```go
func main()  {
	fmt.Printf("current mode: %v, random int: %v\n", os.Getenv("MODE"), fastrand.Intn(10))
	strs := [3]string{"https://github.com", "idealism-xxm", "debugging-go-in-docker-with-goland-and-vscode"}
	url := strings.Join(strs[:], "/")
	fmt.Println(url)
}
```

##### 用 GoLand 调试 Docker 内的 Go 应用

首先我们可以在 GoLand 里打开 `Run/Debug Configurations -> + -> Go Remote` ，就可以看见展示了使用 dlv 调试的方法

![Find Go Remote](img/1.%20Find%20Go%20Remote.gif)

总共有两种方式可以使用 `Go Remote` 进行调试：
- 运行 `dlv debug --headless --listen=:2345 --api-version=2 --accept-multiclient`: 使用 dlv 编译代码并进行调试
- 先运行 `go build -gcflags \"all=-N -l\" github.com/app/demo` ，再运行 `dlv --listen=:2345 --headless=true --api-version=2 --accept-multiclient exec ./demo`: 使用自定义的编译参数编译 Go 应用，然后使用 dlv 进行调试

第二种方法可以自定义编译参数，比较通用，也更符合生产时的编译场景，所以我们采用这种方法进行调试。

接下来就是准备调试用的镜像了，由于 dlv 调试工具不变，所以我们可以先把 dlv 打进基础镜像中，这样可以加速后续编译应用程序的速度。但仅仅是这样还不够，按照这种方式实际操作下来，发现每次编译应用程序时都会重新拉一遍所有的依赖并且重新编译依赖，与本地开发时的体验存在区别，十分耗时。所以想到可以把依赖编译缓存也打进基础镜像中，这样在编译应用程序时就无须额外的下载和编译了，基本和本地开发时的速度一致。

使用如下 `Dockerfile.debug.base` 创建调试用的基础镜像：

```dockerfile
FROM golang:1.14.4

# 构建 dlv 调试工具
RUN go get github.com/go-delve/delve/cmd/dlv

# 先在 debug 的基础镜像中编译一下项目文件，
# 使得改完代码再次编译时能使用当前编译的依赖缓存，加快 debug 镜像的编译
# 若更改了 go.mod 文件，最好重新编译 debug 基础镜像
WORKDIR /github.com/idealism-xxm
COPY . .
RUN mkdir bin
RUN CGO_ENABLED=0 GOOS=linux go build -v -o bin debugging-go-in-docker/...
# 删除对应的文件，方便后续实际编译应用程序
RUN rm -rf /github.com/idealism-xxm
```

运行 `docker build -t debugging-go-in-docker-base:debug -f Dockerfile.debug.base .` 即可得到调试用的基础镜像。

调试所用镜像的 `Dockerfile` 基本会和生产环境一致，改写一下即可得到对应的 `Dockerfile.debug` ：

```dockerfile
FROM debugging-go-in-docker-base:debug

WORKDIR /go/release
COPY . .

# 进行编译
RUN mkdir bin
RUN CGO_ENABLED=0 GOOS=linux go build -v -o bin debugging-go-in-docker/...

WORKDIR /github.com/idealism-xxm/debugging-go-in-docker
# 将编译后的文件拷贝至工作目录
RUN cp -r /go/release/bin/* /github.com/idealism-xxm/debugging-go-in-docker
```

运行 `docker build -t debugging-go-in-docker:debug -f Dockerfile.debug .` 即可得到调试用的镜像。

为了方便创建镜像、启动容器、重启容器，我们可以再写一个 `docker-compose-debug.yml` 文件：

```yaml
version: '3'
services:
  debugging-go-in-docker:
    build:
      dockerfile: Dockerfile.debug
      context: .
    image: debugging-go-in-docker:debug
    environment:
      - MODE=debug
    ports:
      # 这个端口用于远程调试使用，如果程序还需要其他端口，写在后面即可
      - "2345:2345"
    security_opt:
      # 要在没有安全配置文件的情况下运行容器
      - apparmor=unconfined
    cap_add:
      # dlv 调试需要
      - SYS_PTRACE
    # dlv 调试运行的命令
    command: ["/go/bin/dlv", "--listen=:2345", "--headless=true", "--api-version=2", "--accept-multiclient", "exec", "/github.com/idealism-xxm/debugging-go-in-docker/debugging-go-in-docker"]
```

运行 `docker-compose -f docker-compose-debug.yml up -d --build --force-recreate debugging-go-in-docker` 即可每次重新创建镜像，并重新启动容器。

为了方便团队内其他人使用，我们可以把上述的命令写入 `Makefile` 中：

```makefile
.PHONY: build-debug-base build-debug

build-debug-base:
	docker build -t debugging-go-in-docker-base:debug -f Dockerfile.debug.base .

build-debug:
	docker build -t debugging-go-in-docker:debug -f Dockerfile.debug .


.PHONY: debug

debug:
	# --build 每次都构建镜像， --force-recreate 每次都重新创建容器，方便快速重启新的调试
	docker-compose -f docker-compose-debug.yml up -d --build --force-recreate debugging-go-in-docker
```

但仅仅这样还是不够，与本地开发的调试还有一定的差距，目前这样调试我们还需要两步操作：先运行 `make debug` 启动调试服务端，再点击调试按钮启动调试客户端。我们可以发现 GoLand 提供了一个 `Before launch` 可以让我们在启动调试客户端前运行其他的任务，而这个任务正好支持 `Configuration` ，并且 `Configuration` 支持 `Makefile` 这个类型，所以我们可以让启动调试客户端前启动调试服务端。

![Setup Go Remote](img/Setup%20Go%20Remote.gif)

![Debug with GoLand](img/Debug%20with%20GoLand.gif)

##### 用 VSCode 调试 Docker 内的 Go 应用

我们已经在上面的内容中创建好了调试所需的所有必备代码， VSCode 中调试也需要利用这些代码，与 GoLand 调试不同之处仅在配置方式。

为了在 VSCode 中进行调试，我们首先需要配置 `.vscode/launch.json` 文件：

```json5
{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
        {
            // 配置名称，用以区分多个不同的配置
            "name": "debug",
            // 用于运行 go
            "type": "go",
            // 请求的类型
            "request": "attach",
            // 远程调试
            "mode": "remote",
            // 远程源代码的路径
            "remotePath": "/go/release",
            // dlv 调试服务端监听的端口
            "port": 2345,
            // dlv 调试服务端监听的地址
            "host": "127.0.0.1",
            // 展示 debug 日志
            "showLog": true,
            // 运行本配置前需要运行 debug 这个任务
            "preLaunchTask": "debug"
        }
    ]
}
```

可以发现 `VSCode` 也提供了一个 `preLaunchTask` 配置，让我们可以在启动调试客户端前先启动调试服务端。

`debug` 这个任务可以在 `.vscode/tasks.json` 内设置：

```json5
{
    // See https://go.microsoft.com/fwlink/?LinkId=733558
    // for the documentation about the tasks.json format
    "version": "2.0.0",
    "tasks": [
        {
            // 任务的名称
            "label": "debug",
            // 类型为 shell
            "type": "shell",
            // 运行的命令
            "command": "make debug"
        }
    ]
}
```

现在我们就可以在 VSCode 中进行调试了，体验和本地一样顺畅。

![Debug with VSCode](img/Debug%20with%20VSCode.gif)
