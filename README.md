# ssh-copy-id for PowerShell

在 Windows PowerShell 中将一个 SSH 公钥写入远程账户的 `authorized_keys`。

## 环境要求

- Windows PowerShell 5.1 或 Windows 上的 PowerShell 7。
- 本机 OpenSSH 客户端，`ssh.exe` 和 `ssh-keygen.exe` 可通过 PATH 调用。
- 远程账户已有可用的登录方式，例如密码或已授权的密钥。
- Unix 目标需要 POSIX shell 以及 `awk`、`tail`、`wc`、`tr` 等常用工具。

## 使用

无需下载或克隆仓库，可直接在 PowerShell 中运行：

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/He0xD4C0/ssh-copy-id-powershell/main/ssh-copy-id.ps1'))) -User alice -RemoteHost server.example.com
```

Windows OpenSSH 目标可追加 `-RemotePlatform Windows`：

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/He0xD4C0/ssh-copy-id-powershell/main/ssh-copy-id.ps1'))) -User alice -RemoteHost windows.example.com -RemotePlatform Windows
```

该方式会直接执行仓库 `main` 分支中的脚本；也可先阅读上方脚本源码，再执行。

下载 `ssh-copy-id.ps1` 后，在 PowerShell 中运行：

```powershell
.\ssh-copy-id.ps1 -User alice -RemoteHost server.example.com
```

默认按顺序查找 `$HOME/.ssh/` 下的 `id_ed25519.pub`、`id_ecdsa.pub`、`id_rsa.pub`。

指定公钥和端口：

```powershell
.\ssh-copy-id.ps1 -User alice -RemoteHost server.example.com -IdentityFile "$HOME\.ssh\id_ed25519.pub" -Port 2222
```

Windows OpenSSH 目标需显式选择：

```powershell
.\ssh-copy-id.ps1 -User alice -RemoteHost windows.example.com -RemotePlatform Windows
```

首次连接时，应核对 SSH 主机指纹。脚本不会跳过主机密钥检查，也不会修改服务器认证配置。

## 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `User` | 远程账户名，位置 0，必填 | — |
| `RemoteHost` | 主机名或 IP，位置 1，必填 | — |
| `IdentityFile` | 单个公钥文件的路径 | 自动查找 |
| `Port` | SSH 端口，范围 1–65535 | `22` |
| `RemotePlatform` | `Unix` 或 `Windows` | `Unix` |

## 行为与边界

- 先完整读取并校验公钥，再连接远程主机。拒绝私钥、空文件、多行密钥和带 `authorized_keys` 选项的输入。
- 只传输密钥类型和密钥数据，不传输注释。
- 保留已有条目；追加前处理末尾缺少换行的情况。
- 已有行以相同密钥类型和数据开头时不重复追加。带前置授权选项的条目不参与去重。
- Unix 目录权限设为 `700`，文件权限设为 `600`。
- Windows 分支移除继承，并向当前账户、SYSTEM 和 Administrators 授予完全控制；不会清除其他已有显式 ACL。
- Windows 分支使用用户目录下的 `.ssh/authorized_keys`，不处理 `administrators_authorized_keys` 或服务器自定义的密钥路径。
- 返回 `0` 表示远程写入命令成功，或密钥已存在；非零表示失败。写入成功不代表服务器一定允许该密钥登录。

安装后，使用对应私钥单独验证：

```powershell
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$HOME\.ssh\id_ed25519" alice@server.example.com
```

使用非默认端口时，为该命令补上 `-p`。只有成功完成独立登录，才能确认公钥认证可用。

## 验证情况

已在 Windows PowerShell 5.1 和 PowerShell 7 中，经 `127.0.0.1` 连接 WSL Ubuntu 的临时 SSH 服务完成验证：

- 公钥写入后，使用对应新私钥独立登录成功。
- 原文件无末尾换行时，可正确追加。
- 重复执行后，目标文件 SHA-256 不变。
- Unix 目录和文件权限分别为 `700`、`600`。

本地验证也覆盖了私钥和不存在文件的拒绝路径。Windows 服务端分支尚未完成端到端验证。

## License

[MIT](LICENSE)
