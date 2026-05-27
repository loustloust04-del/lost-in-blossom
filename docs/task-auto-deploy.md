# 任务：GitHub Actions 自动部署 .ipa 到 VPS

## 目标
编译成功后自动把 .ipa 推到 VPS，不再需要手动下载。

## 修改文件
`.github/workflows/build.yml`（或当前的 workflow 文件）

## 在 upload-artifact 步骤之后，添加：

```yaml
    - name: Deploy to VPS
      if: success()
      uses: appleboy/scp-action@v0.1.7
      with:
        host: 172.245.88.103
        port: 48722
        username: root
        key: ${{ secrets.VPS_SSH_KEY }}
        source: "build/LostInBlossom.ipa"
        target: "/root/projects/lib-web/"
        strip_components: 1
```

## 需要的 GitHub Secret
在仓库 Settings > Secrets 里添加 `VPS_SSH_KEY`：VPS 的 SSH 私钥。

## 备选方案（如果 SSH key 不方便配）
用 curl 上传：
```yaml
    - name: Deploy to VPS
      if: success()
      run: |
        curl -X PUT --upload-file build/LostInBlossom.ipa \
          "http://172.245.88.103:3600/upload/LostInBlossom.ipa"
```
（需要在 VPS 的 lib-web 服务里加一个上传端点）

## 效果
猫 push 代码 → GitHub Actions 编译 → 成功 → .ipa 自动出现在 VPS → 天奕直接下载。
主人不用再手动下载 artifact 了。
