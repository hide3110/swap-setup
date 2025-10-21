# swap-setup
适用于 Debian 和 Alpine Linux 的简单通用 swap 配置脚本，一键设置，可自定义大小和 swappiness 值。

### 通过一键脚本自定义安装
自定义端口参数如：SW_SIZE=1G（swap空间大小），SW_NESS=10（swappiness为10%），使用时请自行定义此参数！
```bash
SW_SIZE=1G SW_NESS=10 bash <(curl -fsSL https://raw.githubusercontent.com/hide3110/swap-setup/main/install.sh)
```

### 缷载
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hide3110/swap-setup/main/uninstall.sh)
```
