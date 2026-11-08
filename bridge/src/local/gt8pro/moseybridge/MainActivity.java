package local.gt8pro.moseybridge;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.concurrent.TimeUnit;

public final class MainActivity extends Activity {
 private TextView status;
 private Button restart;
 @Override public void onCreate(Bundle saved) {
  super.onCreate(saved);
  LinearLayout layout=new LinearLayout(this);
  layout.setOrientation(LinearLayout.VERTICAL);
  layout.setPadding(40,48,40,40);
  status=new TextView(this);
  status.setTextSize(16);
  status.setText("使用前请确保已安装配套模块并在 LSPosed 启用桥接。重启时会检查当前传输状态。\n\n此功能需要 Root 授权。");
  restart=new Button(this);
  restart.setText("重启分享服务");
  restart.setOnClickListener(v -> restartService());
  layout.addView(status);
  layout.addView(restart);
  setContentView(layout);
 }
 private void restartService() {
  restart.setEnabled(false);
  status.setText("正在检查服务和传输状态…");
  new Thread(() -> {
   String result="ERROR";
   Process p=null;
   try {
    p=new ProcessBuilder("su","-c","sh /data/adb/modules/gt8pro.mosey.integrated/payload/restart-service.sh")
      .redirectErrorStream(true).start();
    if(p.waitFor(35,TimeUnit.SECONDS)) {
     InputStream in=p.getInputStream();
     ByteArrayOutputStream out=new ByteArrayOutputStream();
     byte[] bytes=new byte[256]; int n; int count=0;
     while((n=in.read(bytes))!=-1 && count<4096) {out.write(bytes,0,Math.min(n,4096-count));count+=n;}
     String response=out.toString("UTF-8");
     if(p.exitValue()==0 && response.contains("RESTART_READY"))result="READY";
     else if(response.contains("TRANSFER_BUSY"))result="BUSY";
     else if(response.contains("MODULE_UNAVAILABLE"))result="MODULE";
     else if(response.contains("SERVICE_ACTIVE"))result="ACTIVE";
    } else {p.destroy();result="TIMEOUT";}
   } catch(Exception ignored) {if(p!=null)p.destroy();}
   final String outcome=result;
   runOnUiThread(() -> {
    restart.setEnabled(true);
    switch(outcome) {
     case "READY":
      status.setText("恢复检查完成，正在打开 Quick Share。请等待服务启动。");
      try {startActivity(new Intent().setComponent(new ComponentName("com.google.android.gms","com.google.android.gms.nearby.sharing.main.MainActivity")));}
      catch(Exception e){status.setText("恢复检查完成，但无法打开 Quick Share。请手动打开分享页面。");}
      break;
     case "BUSY":status.setText("检测到传输进行中或状态不明确，请稍后再试。");break;
     case "ACTIVE":status.setText("服务正在运行。请关闭 Quick Share 页面，等待服务停止后再试。");break;
     case "MODULE":status.setText("未找到兼容的整合模块，请检查模块是否启用。");break;
     case "TIMEOUT":status.setText("操作超时，请检查 Root 授权及服务状态。");break;
     default:status.setText("恢复未完成，请检查 Root 授权及模块状态。");
    }
   });
  },"GT8-Restart").start();
 }
}
