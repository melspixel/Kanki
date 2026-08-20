#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef void (*load_html_fn)(void *web_view, const char *content, const char *base_uri);

static const char kanki_audio_shim[] =
"<script>(function(){"
"if(typeof window.Audio!=='undefined')return;"
"function P(){this.then=function(){return this;};this.catch=function(){return this;};}"
"function ping(path,src){try{var i=new Image();i.style.display='none';"
"i.src='http://127.0.0.1:17392/'+path+'?src='+encodeURIComponent(src||'')+'&t='+(new Date().getTime());"
"(document.body||document.documentElement).appendChild(i);"
"setTimeout(function(){try{i.parentNode&&i.parentNode.removeChild(i);}catch(e){}},1500);}catch(e){}}"
"function A(src){this.src=src||'';this.currentSrc=this.src;this.currentTime=0;this.duration=0;"
"this.paused=true;this.ended=false;this.autoplay=false;this.loop=false;this.muted=false;this.volume=1;this.preload='auto';}"
"A.prototype.play=function(){this.paused=false;this.ended=false;ping('play',this.src);return new P();};"
"A.prototype.pause=function(){this.paused=true;ping('stop','');};"
"A.prototype.load=function(){};A.prototype.addEventListener=function(){};A.prototype.removeEventListener=function(){};"
"window.Audio=A;"
"})();</script>";

static char *inject_shim(const char *content)
{
    const char *head;
    size_t content_len, shim_len, prefix_len;
    char *out;

    if (!content) return NULL;
    if (strstr(content, "127.0.0.1:17392/") != NULL) return NULL;

    content_len = strlen(content);
    shim_len = sizeof(kanki_audio_shim) - 1;
    head = strstr(content, "</head>");
    prefix_len = head ? (size_t)(head - content) : 0;

    out = (char *)malloc(content_len + shim_len + 1);
    if (!out) return NULL;

    if (head) {
        memcpy(out, content, prefix_len);
        memcpy(out + prefix_len, kanki_audio_shim, shim_len);
        memcpy(out + prefix_len + shim_len, head, content_len - prefix_len + 1);
    } else {
        memcpy(out, kanki_audio_shim, shim_len);
        memcpy(out + shim_len, content, content_len + 1);
    }
    return out;
}

void webkit_web_view_load_html_string(void *web_view, const char *content, const char *base_uri)
{
    static load_html_fn real_fn = NULL;
    char *patched;

    if (!real_fn) {
        real_fn = (load_html_fn)dlsym(RTLD_NEXT, "webkit_web_view_load_html_string");
        if (!real_fn) return;
    }

    patched = inject_shim(content);
    if (patched) {
        real_fn(web_view, patched, base_uri);
        free(patched);
    } else {
        real_fn(web_view, content, base_uri);
    }
}
