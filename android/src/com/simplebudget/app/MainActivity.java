package com.simplebudget.app;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity {
    private WebView web;

    /** 把记账数据存到 SharedPreferences，比 WebView 的 file:// localStorage 稳。 */
    public class StorageBridge {
        private final SharedPreferences sp;
        StorageBridge(Context c) {
            sp = c.getSharedPreferences("budget_store", Context.MODE_PRIVATE);
        }
        @JavascriptInterface
        public String get(String key) {
            return sp.getString(key, null);
        }
        @JavascriptInterface
        public void set(String key, String value) {
            sp.edit().putString(key, value).commit();
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Window w = getWindow();
        w.setStatusBarColor(Color.parseColor("#F2F3F5"));
        w.setNavigationBarColor(Color.parseColor("#F2F3F5"));
        if (Build.VERSION.SDK_INT >= 23) {
            w.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
        }

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(true);
        s.setAllowFileAccessFromFileURLs(true);
        s.setAllowUniversalAccessFromFileURLs(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);

        web.setBackgroundColor(Color.parseColor("#F2F3F5"));
        web.setWebViewClient(new WebViewClient());
        web.addJavascriptInterface(new StorageBridge(this), "AndroidStore");
        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");
    }

    @Override
    public void onBackPressed() {
        // 如果弹出层开着，先关弹出层；否则退出。
        web.evaluateJavascript(
            "(function(){var s=document.getElementById('sheet');return !!(s&&s.classList.contains('show'));})()",
            new ValueCallback<String>() {
                @Override
                public void onReceiveValue(String value) {
                    if ("true".equals(value)) {
                        web.evaluateJavascript(
                            "document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));", null);
                    } else if (web.canGoBack()) {
                        web.goBack();
                    } else {
                        finish();
                    }
                }
            });
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (web != null) web.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) web.onResume();
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        super.onDestroy();
    }
}
