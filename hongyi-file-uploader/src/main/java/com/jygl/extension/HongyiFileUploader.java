package com.jygl.extension;

import com.netease.lowcode.core.annotation.NaslLogic;

import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.entity.mime.MultipartEntityBuilder;
import org.apache.http.entity.ContentType;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;

public class HongyiFileUploader {

    /**
     * 上传文件到鸿翼 /document/upload（v1.0.4）
     * 平台临时文件 URL → 下载字节 → multipart 转发鸿翼
     *
     * @param fileUrl      平台临时文件 URL（文件上传组件返回值，如 http://host/upload/test.txt?fileName=...）
     * @param regionHash   上传第一步 CheckAndCreateDocInfo 返回
     * @param regionId     上传第一步返回（1=主站点）
     * @param uploadId     前端生成的 GUID
     * @param token        教师鸿翼 token
     * @param uploadServer 区域站点地址（RegionUrl；为空默认主站点）
     * @return 鸿翼响应 body（status=End 即成功）
     */
    @NaslLogic
    public static String uploadToHongyi(
            String fileUrl,
            String regionHash,
            Integer regionId,
            String uploadId,
            String token,
            String uploadServer
    ) {
        try {
            CloseableHttpClient httpClient = HttpClients.createDefault();

            // ========== 1. 下载平台临时文件 ==========
            HttpGet httpGet = new HttpGet(fileUrl);
            CloseableHttpResponse downloadResp = httpClient.execute(httpGet);
            int downloadCode = downloadResp.getStatusLine().getStatusCode();
            byte[] fileBytes = EntityUtils.toByteArray(downloadResp.getEntity());
            downloadResp.close();
            if (downloadCode != 200 || fileBytes.length == 0) {
                httpClient.close();
                return "{\"status\":\"Error\",\"errorCode\":\"9001\",\"msg\":\"平台文件下载失败 HTTP " + downloadCode + "\"}";
            }

            // ========== 2. 解析文件名（URL 路径末段） ==========
            String fileName = parseFileName(fileUrl);

            // ========== 3. 组装上传地址 ==========
            String host = (uploadServer != null && !uploadServer.isEmpty())
                    ? uploadServer : "http://<内网地址·已脱敏>:30179";
            String uploadUrl = host + "/document/upload?code=&token=" + token;

            // ========== 4. multipart 转发鸿翼 ==========
            HttpPost httpPost = new HttpPost(uploadUrl);
            MultipartEntityBuilder builder = MultipartEntityBuilder.create();
            builder.addTextBody("uploadId", uploadId);
            builder.addTextBody("regionHash", regionHash);
            builder.addTextBody("regionId", String.valueOf(regionId));
            builder.addTextBody("fileName", fileName);
            builder.addTextBody("size", String.valueOf(fileBytes.length));
            builder.addTextBody("chunks", "1");
            builder.addTextBody("chunk", "0");
            builder.addTextBody("chunkSize", "5242880");
            builder.addTextBody("blockSize", String.valueOf(fileBytes.length));
            builder.addBinaryBody("file", fileBytes, ContentType.APPLICATION_OCTET_STREAM, fileName);

            httpPost.setEntity(builder.build());

            CloseableHttpResponse response = httpClient.execute(httpPost);
            String body = EntityUtils.toString(response.getEntity(), "UTF-8");
            int statusCode = response.getStatusLine().getStatusCode();
            response.close();
            httpClient.close();

            return body;

        } catch (Exception e) {
            return "{\"status\":\"Error\",\"errorCode\":\"9002\",\"msg\":\""
                    + escapeJson(e.getClass().getSimpleName() + ": " + e.getMessage()) + "\"}";
        }
    }

    /** 从 URL 路径末段解析文件名（/upload/test.txt?xxx → test.txt） */
    private static String parseFileName(String fileUrl) {
        try {
            String path = new java.net.URL(fileUrl).getPath();
            int idx = path.lastIndexOf('/');
            return idx >= 0 ? path.substring(idx + 1) : "file";
        } catch (Exception e) {
            return "file";
        }
    }

    private static String escapeJson(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r");
    }
}
