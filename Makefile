# go2shell Makefile
# 使用 Swift Package Manager 构建 macOS 应用

.PHONY: all build build-extensions build-terminal-ext build-copy-ext create-bundle \
        codesign verify clean install uninstall run test help icon icon-source \
        reset debug release

# 变量定义
APP_NAME = go2shell
BUNDLE_ID = com.solarhell.go2shell
BUILD_DIR = .build
# 注意：swift build --arch 的产物在 .build/apple/Products/Release，不是 .build/release
RELEASE_DIR = $(BUILD_DIR)/apple/Products/Release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
INSTALL_PATH = /Applications/$(APP_NAME).app
DIST_DIR = build

# 版本号：以最近的 git tag 为准，脱离 git 构建时回落到 Info.plist 里的值。
# 三个 bundle 必须写同一个版本，容器 app 和 appex 版本不一致会被系统拒绝加载。
DETECTED_APP_VERSION = $(shell git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null | sed 's/^v//')
PLIST_APP_VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 0.0.0)
APP_VERSION ?= $(if $(DETECTED_APP_VERSION),$(DETECTED_APP_VERSION),$(PLIST_APP_VERSION))
APP_BUILD ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

# 通用二进制：Apple Silicon + Intel，三个可执行文件都必须包含这两个架构
ARCHS = arm64 x86_64
SWIFT_ARCH_FLAGS = $(foreach arch,$(ARCHS),--arch $(arch))

# FinderSync 扩展
SDK_PATH := $(shell xcrun --show-sdk-path --sdk macosx)
DEPLOYMENT_TARGET = macosx15.0
EXT_DIR = FinderSyncExtension
ARCH_TMP = $(BUILD_DIR)/ext-arch
TERM_EXT = $(BUILD_DIR)/go2shellTerminal.appex
COPY_EXT = $(BUILD_DIR)/go2shellCopy.appex

EXT_SWIFTC_FLAGS = -sdk $(SDK_PATH) \
                   -O -parse-as-library \
                   -Xlinker -e -Xlinker _NSExtensionMain \
                   -framework Foundation -framework AppKit -framework FinderSync

TERM_SOURCES = $(EXT_DIR)/TerminalSync/FinderSyncController.swift \
               $(EXT_DIR)/TerminalSync/TerminalLauncher.swift \
               $(EXT_DIR)/TerminalSync/main.swift

COPY_SOURCES = $(EXT_DIR)/CopySync/FinderSyncController.swift \
               $(EXT_DIR)/CopySync/main.swift

# 把版本号写进已复制到 bundle 里的 Info.plist（源文件不动）
define set-version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(APP_VERSION)" $(1) && \
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(APP_BUILD)" $(1)
endef

# 默认目标
all: build

# 显示帮助信息
help:
	@echo "go2shell 构建系统 (基于 Swift Package Manager)"
	@echo ""
	@echo "可用命令:"
	@echo "  make build       - 构建通用二进制应用（默认，$(ARCHS)）"
	@echo "  make verify      - 校验产物是否包含全部架构"
	@echo "  make clean       - 清理构建文件"
	@echo "  make install     - 安装到 /Applications"
	@echo "  make uninstall   - 从 /Applications 卸载"
	@echo "  make run         - 运行应用（设置界面）"
	@echo "  make release     - 打包 zip + sha256（本地等价于 CI 打包）"
	@echo "  make icon-source - 用 generate_icon.swift 生成 Resources/icon.png"
	@echo "  make icon        - 把 icon.png 转成 AppIcon.icns"
	@echo "  make reset       - 重启 Finder"
	@echo "  make debug       - 显示调试信息"
	@echo ""

# 构建应用
build:
	@echo "🔨 开始构建 go2shell（通用二进制: $(ARCHS)）..."
	@echo ""

	# 使用 SPM 构建 Release 版本
	@echo "📦 使用 Swift Package Manager 编译主应用..."
	@swift build -c release $(SWIFT_ARCH_FLAGS)
	@echo "✅ 主应用编译完成"
	@echo ""

	# 构建 FinderSync 扩展
	@echo "🔌 构建 FinderSync 扩展..."
	@$(MAKE) --no-print-directory build-extensions
	@echo "✅ 扩展构建完成"
	@echo ""

	# 创建 App Bundle
	@echo "📁 创建 App Bundle 结构..."
	@$(MAKE) --no-print-directory create-bundle
	@echo "✅ App Bundle 创建完成"
	@echo ""

	# 代码签名
	@echo "✍️  代码签名..."
	@$(MAKE) --no-print-directory codesign
	@echo "✅ 代码签名完成"
	@echo ""

	# 架构校验
	@echo "🔍 校验架构..."
	@$(MAKE) --no-print-directory verify
	@echo ""

	@echo "✅ 构建完成！"
	@echo "📦 应用位置: $(APP_BUNDLE)"
	@echo ""
	@echo "下一步: make install"

# 构建两个 FinderSync .appex（逐架构编译后 lipo 合并）
build-extensions: build-terminal-ext build-copy-ext

build-terminal-ext:
	@echo "  → Building TerminalSync extension ($(ARCHS))"
	@rm -rf $(TERM_EXT) $(ARCH_TMP)/TerminalSync
	@mkdir -p $(TERM_EXT)/Contents/MacOS
	@mkdir -p $(TERM_EXT)/Contents/Resources
	@mkdir -p $(ARCH_TMP)/TerminalSync
	@for arch in $(ARCHS); do \
	                swiftc -target $$arch-apple-$(DEPLOYMENT_TARGET) $(EXT_SWIFTC_FLAGS) \
	                       -o $(ARCH_TMP)/TerminalSync/go2shellTerminal-$$arch \
	                       $(TERM_SOURCES) || exit 1; \
	        done
	@lipo -create $(foreach arch,$(ARCHS),$(ARCH_TMP)/TerminalSync/go2shellTerminal-$(arch)) \
	             -output $(TERM_EXT)/Contents/MacOS/go2shellTerminal
	@cp $(EXT_DIR)/TerminalSync/Info.plist $(TERM_EXT)/Contents/Info.plist
	@$(call set-version,$(TERM_EXT)/Contents/Info.plist)
	@codesign --force --sign - \
	        --entitlements $(EXT_DIR)/TerminalSync/FinderSync.entitlements \
	        $(TERM_EXT)

build-copy-ext:
	@echo "  → Building CopySync extension ($(ARCHS))"
	@rm -rf $(COPY_EXT) $(ARCH_TMP)/CopySync
	@mkdir -p $(COPY_EXT)/Contents/MacOS
	@mkdir -p $(COPY_EXT)/Contents/Resources
	@mkdir -p $(ARCH_TMP)/CopySync
	@for arch in $(ARCHS); do \
	                swiftc -target $$arch-apple-$(DEPLOYMENT_TARGET) $(EXT_SWIFTC_FLAGS) \
	                       -o $(ARCH_TMP)/CopySync/go2shellCopy-$$arch \
	                       $(COPY_SOURCES) || exit 1; \
	        done
	@lipo -create $(foreach arch,$(ARCHS),$(ARCH_TMP)/CopySync/go2shellCopy-$(arch)) \
	             -output $(COPY_EXT)/Contents/MacOS/go2shellCopy
	@cp $(EXT_DIR)/CopySync/Info.plist $(COPY_EXT)/Contents/Info.plist
	@$(call set-version,$(COPY_EXT)/Contents/Info.plist)
	@codesign --force --sign - \
	        --entitlements $(EXT_DIR)/CopySync/FinderSync.entitlements \
	        $(COPY_EXT)

# 创建 App Bundle 结构
create-bundle:
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@mkdir -p $(APP_BUNDLE)/Contents/PlugIns

	# 复制主应用可执行文件
	@cp $(RELEASE_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/

	# 嵌入 FinderSync 扩展
	@cp -R $(TERM_EXT) $(APP_BUNDLE)/Contents/PlugIns/
	@cp -R $(COPY_EXT) $(APP_BUNDLE)/Contents/PlugIns/

	# 复制 SPM resource bundle（本地化资源等）
	@for bundle in $(RELEASE_DIR)/*.bundle; do \
	                if [ -d "$$bundle" ]; then \
	                        cp -r "$$bundle" $(APP_BUNDLE)/Contents/Resources/; \
	                fi; \
	        done

	# 复制主应用配置
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@$(call set-version,$(APP_BUNDLE)/Contents/Info.plist)

	# 复制图标（如果存在）
	@if [ -f Resources/AppIcon.icns ]; then \
	                cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/; \
	        fi

	# 复制本地化资源
	@for lproj in Resources/*.lproj; do \
	                if [ -d "$$lproj" ]; then \
	                        cp -r "$$lproj" $(APP_BUNDLE)/Contents/Resources/; \
	                fi; \
	        done

# 代码签名（扩展已在 build 阶段单独签名，此处只签主 app）
codesign:
	# 先确保嵌入的扩展签名完好
	@codesign --force --sign - \
	        --entitlements $(EXT_DIR)/TerminalSync/FinderSync.entitlements \
	        $(APP_BUNDLE)/Contents/PlugIns/go2shellTerminal.appex
	@codesign --force --sign - \
	        --entitlements $(EXT_DIR)/CopySync/FinderSync.entitlements \
	        $(APP_BUNDLE)/Contents/PlugIns/go2shellCopy.appex
	# 签名主应用（不 --deep，避免覆盖扩展 entitlements）
	@codesign --force --sign - \
	        --entitlements Resources/go2shell.entitlements \
	        $(APP_BUNDLE)

# 校验三个可执行文件都是通用二进制（防止再发出单架构包）
verify:
	@for bin in $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) \
	                   $(APP_BUNDLE)/Contents/PlugIns/go2shellTerminal.appex/Contents/MacOS/go2shellTerminal \
	                   $(APP_BUNDLE)/Contents/PlugIns/go2shellCopy.appex/Contents/MacOS/go2shellCopy; do \
	                if [ ! -f "$$bin" ]; then echo "  ✗ 缺少 $$bin"; exit 1; fi; \
	                got=$$(lipo -archs "$$bin"); \
	                for want in $(ARCHS); do \
	                        case " $$got " in \
	                                *" $$want "*) ;; \
	                                *) echo "  ✗ $$(basename $$bin) 缺少 $$want（实际: $$got）"; exit 1;; \
	                        esac; \
	                done; \
	                echo "  ✓ $$(basename $$bin): $$got"; \
	        done

# 清理构建文件
clean:
	@echo "🧹 清理构建文件..."
	@swift package clean
	@rm -rf $(BUILD_DIR)
	@rm -rf $(DIST_DIR)
	@rm -rf .swiftpm
	@echo "✅ 清理完成"

# 安装到 /Applications
install: build
	@echo "📦 安装 go2shell 到 /Applications..."
	@if [ -d "$(INSTALL_PATH)" ]; then \
	                echo "⚠️  $(INSTALL_PATH) 已存在，将覆盖"; \
	                rm -rf "$(INSTALL_PATH)"; \
	        fi
	@cp -r $(APP_BUNDLE) $(INSTALL_PATH)
	@echo "✅ 应用已安装到 $(INSTALL_PATH)"
	@echo ""
	@echo "🔌 重新注册 App 与 FinderSync 扩展..."
	# lsregister -f 触发 LaunchServices 重新扫描整个 app，pluginkit 也会 re-index
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f $(INSTALL_PATH)
	@sleep 1
	@pluginkit -a $(INSTALL_PATH)/Contents/PlugIns/go2shellTerminal.appex
	@pluginkit -a $(INSTALL_PATH)/Contents/PlugIns/go2shellCopy.appex
	@pluginkit -e use -i com.solarhell.go2shell.TerminalSync
	@pluginkit -e use -i com.solarhell.go2shell.CopySync
	@sleep 2
	@if pluginkit -m -v 2>/dev/null | grep -q "com.solarhell.go2shell.TerminalSync"; then \
	                echo "  ✓ TerminalSync 已注册"; \
	        else \
	                echo "  ✗ TerminalSync 未注册"; exit 1; \
	        fi
	@if pluginkit -m -v 2>/dev/null | grep -q "com.solarhell.go2shell.CopySync"; then \
	                echo "  ✓ CopySync 已注册"; \
	        else \
	                echo "  ✗ CopySync 未注册"; exit 1; \
	        fi
	@killall Finder 2>/dev/null || true
	@echo "✅ Finder 已重启"
	@echo ""

# 卸载
uninstall:
	@echo "🗑️  卸载 go2shell..."
	@if [ -d "$(INSTALL_PATH)" ]; then \
	                rm -rf "$(INSTALL_PATH)"; \
	                echo "✅ 已卸载 $(INSTALL_PATH)"; \
	        else \
	                echo "⚠️  $(INSTALL_PATH) 不存在"; \
	        fi
	@echo ""
	@echo "💡 如需完全清理，还可以运行:"
	@echo "   rm -rf ~/Library/Group\\ Containers/group.$(BUNDLE_ID)"

# 运行应用（设置界面）
# main.swift 只认 --show-ui：不带参数时是否弹窗取决于 Finder 是否在前台
run: build
	@echo "🪟 运行 go2shell (设置界面)..."
	@$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) --show-ui

# 生成图标源图（1024x1024 PNG）
icon-source:
	@echo "🎨 生成 Resources/icon.png..."
	@swift generate_icon.swift
	@echo "💡 下一步: make icon"

# 生成图标
icon:
	@if [ ! -f "Resources/icon.png" ]; then \
	                echo "❌ 未找到 Resources/icon.png"; \
	                echo "请先运行 make icon-source，或自备一个 1024x1024 的 PNG"; \
	                exit 1; \
	        fi
	@echo "🎨 生成应用图标..."
	@mkdir -p $(BUILD_DIR)/AppIcon.iconset
	@sips -z 16 16     Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16.png >/dev/null
	@sips -z 32 32     Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16@2x.png >/dev/null
	@sips -z 32 32     Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32.png >/dev/null
	@sips -z 64 64     Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32@2x.png >/dev/null
	@sips -z 128 128   Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128.png >/dev/null
	@sips -z 256 256   Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128@2x.png >/dev/null
	@sips -z 256 256   Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256.png >/dev/null
	@sips -z 512 512   Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256@2x.png >/dev/null
	@sips -z 512 512   Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512.png >/dev/null
	@sips -z 1024 1024 Resources/icon.png --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512@2x.png >/dev/null
	@iconutil -c icns $(BUILD_DIR)/AppIcon.iconset -o Resources/AppIcon.icns
	@rm -rf $(BUILD_DIR)/AppIcon.iconset
	@echo "✅ 图标生成完成: Resources/AppIcon.icns"

# 打包 Release zip（用于 Homebrew Cask 分发），产物与 build.yml 保持一致
release: build
	@echo "📦 打包 Release..."
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/$(APP_NAME).zip $(DIST_DIR)/$(APP_NAME).zip.sha256
	@cd $(BUILD_DIR) && zip -qry ../$(DIST_DIR)/$(APP_NAME).zip $(APP_NAME).app
	@shasum -a 256 $(DIST_DIR)/$(APP_NAME).zip | awk '{print $$1}' > $(DIST_DIR)/$(APP_NAME).zip.sha256
	@echo "✅ 打包完成: $(DIST_DIR)/$(APP_NAME).zip"
	@echo "   sha256: $$(cat $(DIST_DIR)/$(APP_NAME).zip.sha256)"

# 运行测试
test:
	@echo "ℹ️  Package.swift 没有声明测试 target，当前仓库没有可运行的测试。"

# 重置 Finder
reset:
	@echo "🔄 重置 Finder..."
	@killall Finder || true
	@echo "✅ 重置完成"

# 调试信息
debug:
	@echo "🔍 调试信息"
	@echo "============"
	@echo "Swift 版本:"
	@swift --version
	@echo ""
	@echo "目标架构: $(ARCHS)"
	@echo "版本号: $(APP_VERSION) (build $(APP_BUILD))"
	@echo ""
	@echo "应用状态:"
	@if [ -d "$(INSTALL_PATH)" ]; then \
	                echo "✅ 已安装: $(INSTALL_PATH)"; \
	                echo "   架构: $$(lipo -archs $(INSTALL_PATH)/Contents/MacOS/$(APP_NAME))"; \
	        else \
	                echo "❌ 未安装"; \
	        fi
