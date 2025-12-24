# GBB
[English docs](./Readme_en.md)

Gemini Build Builder (GBB) 是一个帮助将 Gemini ["Build your ideas with Gemini"](https://aistudio.google.com/apps) 功能生成的代码 zip 一键打包为离线应用的小工具。
GBB 对 Gemini 2.5 到 3 之间的版本有较全面的适配，但不推荐用于打包需要 API 调用的 APPs（需要手动修改变量等）。

## 前置要求
[Node.js & npm](https://nodejs.org/): 建议安装 LTS 版本。

## 使用方法
（Win）将 zip 拖到 gbb.bat 上，或者
```powershell
# Win
gbb path/to/source.zip
```
```sh
# Linux/MacOS (experimental / not fully stable)
bash gbb.sh /path/to/source.zip
```

产物会以在对应平台的安装包、html、携带版应用的形式保存在 output 文件夹中。

## 未来计划
1. 收集 gemini 生成代码的数据集，提升此工具的兼容性。
2. ...待定，欢迎提出建议。