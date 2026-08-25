# Battuta Windows 安装与签名

这里的清单和脚本已经接入真实 MSIX 构建，不再是占位文件。安装包为自包含的
Windows 桌面应用，最低系统版本是 Windows 10 2004（build 19041）。

## 开发测试包

在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File BattutaWindows/scripts/Publish-Msix.ps1 `
  -Version 0.1.0 `
  -BuildNumber 1 `
  -SigningMode Development
```

脚本会创建或复用当前用户证书存储中的
`CN=Wormforce Battuta Development` 开发证书，并输出：

- `Battuta-Windows-0.1.0-win-x64-dev.msix`
- `Battuta-Windows-Development.cer`
- MSIX 对应的 `.sha256` 文件

开发证书不是公开发布身份。安装测试包需要明确地以管理员身份运行：

```powershell
powershell -ExecutionPolicy Bypass -File BattutaWindows/scripts/Install-MsixDevelopment.ps1 `
  -PackagePath BattutaWindows/artifacts/Battuta-Windows-0.1.0-win-x64-dev.msix `
  -CertificatePath BattutaWindows/artifacts/Battuta-Windows-Development.cer
```

该操作会把开发证书加入本机 `TrustedPeople`。只在受控测试电脑上使用；测试完成后，
可以从“管理计算机证书”中删除 `Wormforce Battuta Development`。

## Microsoft Store 包

先在 Partner Center 预留应用名称，然后复制 Store 提供的 Package identity name、
Publisher 和 Publisher display name。示例：

```powershell
powershell -ExecutionPolicy Bypass -File BattutaWindows/scripts/Publish-Msix.ps1 `
  -Version 1.0.0 `
  -BuildNumber 0 `
  -PackageName '<Partner Center identity name>' `
  -Publisher '<Partner Center publisher>' `
  -PublisherDisplayName '<Partner Center display name>' `
  -SigningMode None `
  -StoreSubmission
```

这个未签名 MSIX 只用于提交 Store，不能放到网站让用户直接安装。Store 认证后会用
Microsoft 证书重新签名。

## 官网直接发布

官网直发需要受 Windows 信任的代码签名证书。证书必须位于当前用户的 `My` 存储，
且 Manifest Publisher 必须与证书 Subject 完全一致：

```powershell
powershell -ExecutionPolicy Bypass -File BattutaWindows/scripts/Publish-Msix.ps1 `
  -Version 0.1.0 `
  -BuildNumber 1 `
  -PackageName 'Wormforce.Battuta' `
  -Publisher '<certificate subject>' `
  -PublisherDisplayName 'Wormforce' `
  -SigningMode CertificateStore `
  -SigningCertificateThumbprint '<certificate thumbprint>' `
  -TimestampUri 'https://<CA timestamp endpoint>' `
  -AppInstallerBaseUri 'https://www.wormforce.net/downloads/battuta/windows'
```

提供 `AppInstallerBaseUri` 后还会生成 `Battuta.appinstaller`。服务器必须支持 HTTPS、
GET 和 HEAD，并返回正确的 `Content-Type`：

- `.appinstaller`: `application/appinstaller`
- `.msix`: `application/msix`

同一张正式证书也可以签署便携版中的 `Battuta.exe`：

```powershell
powershell -ExecutionPolicy Bypass -File BattutaWindows/scripts/Publish-Portable.ps1 `
  -Version 0.1.0 `
  -SigningCertificateThumbprint '<certificate thumbprint>' `
  -TimestampUri 'https://<CA timestamp endpoint>'
```

## 发布约束

- 首次公开发布后，Package Name 和 Publisher 永远保持不变。
- 每次更新的四段 MSIX 版本必须严格递增。
- Store 包的第一段版本不能为 0，第四段必须为 0；首次 Store 包使用 `1.0.0.0`。
- Store 身份、证书私钥、密码和签名 token 不得提交到仓库。
- `.simuboardpack` 当前是目录包，不是普通文件，因此 MSIX 不声明虚假的文件关联。
- 登录启动通过 `BattutaStartup` 注册，并用 `--startup` 参数静默启动托盘进程。
- `.appinstaller` 负责 MSIX 自动更新；便携 ZIP 仍使用 GitHub Release 手动替换。
