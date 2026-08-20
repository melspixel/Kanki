#define _GNU_SOURCE
typedef unsigned int size_t;
extern void *malloc(size_t);
extern void free(void *);
extern void *dlsym(void *, const char *);
#define RTLD_NEXT ((void *)-1L)
#define NULL ((void*)0)

static size_t k_strlen(const char *s){size_t n=0; while(s && s[n]) n++; return n;}
static void k_memcpy(char *d,const char *s,size_t n){while(n--) *d++=*s++;}
static const char *k_strstr(const char *h,const char *n){size_t nl=k_strlen(n); if(!nl) return h; for(;h&&*h;h++){size_t i=0; while(i<nl&&h[i]==n[i]) i++; if(i==nl) return h;} return (const char*)0;}

typedef void (*load_html_fn)(void *web_view, const char *content, const char *base_uri);
typedef void (*set_zoom_fn)(void *web_view, float zoom_level);

/*
 * Kindle's WebKit is old and Ranki multiplies its card zoom by screen-width
 * scaling.  On modern 1200px-class Paperwhites that can push the effective
 * zoom above 3x.  This shim both supplies missing Anki audio behavior and
 * applies conservative Kindle-specific presentation fixes.
 */
static const char kanki_audio_shim[] =
"<script>(function(){"
"function addStyle(){try{var h=document.getElementsByTagName('head')[0]||document.documentElement;"
"var s=document.createElement('style');s.type='text/css';"
"var css='html{-webkit-text-size-adjust:100%;}body{overflow-x:hidden;}' +"
"'.kanki-audio-link{font-size:20px!important;line-height:24px!important;display:inline-block!important;vertical-align:middle!important;text-decoration:none!important;padding:1px 5px!important;margin:0 2px!important;width:auto!important;height:auto!important;}' +"
"'.kindle .replay-button,.kindle .soundLink,.kindle .audio-button{font-size:20px!important;line-height:24px!important;max-width:40px!important;max-height:40px!important;width:auto!important;height:auto!important;}' +"
"'.kindle .replay-button svg,.kindle .soundLink svg,.kindle .audio-button svg,.kindle button svg{width:28px!important;height:28px!important;max-width:28px!important;max-height:28px!important;}' +"
"'.kindle img{max-width:100%!important;height:auto;}';"
"if(s.styleSheet)s.styleSheet.cssText=css;else s.appendChild(document.createTextNode(css));h.appendChild(s);}catch(e){}}"
"function ping(path,src){try{var i=new Image();i.style.display='none';"
"i.src='http://127.0.0.1:17392/'+path+'?src='+encodeURIComponent(src||'')+'&t='+(new Date().getTime());"
"(document.body||document.documentElement).appendChild(i);"
"setTimeout(function(){try{i.parentNode&&i.parentNode.removeChild(i);}catch(e){}},1500);}catch(e){}}"
"window.__kankiAudioPing=ping;"
"if(typeof window.Audio==='undefined'){"
"function P(){this.then=function(){return this;};this.catch=function(){return this;};}"
"function A(src){this.src=src||'';this.currentSrc=this.src;this.currentTime=0;this.duration=0;"
"this.paused=true;this.ended=false;this.autoplay=false;this.loop=false;this.muted=false;this.volume=1;this.preload='auto';}"
"A.prototype.play=function(){this.paused=false;this.ended=false;ping('play',this.src);return new P();};"
"A.prototype.pause=function(){this.paused=true;ping('stop','');};"
"A.prototype.load=function(){};A.prototype.addEventListener=function(){};A.prototype.removeEventListener=function(){};"
"window.Audio=A;"
"}"
"function replaceSoundText(node,sounds){"
"if(!node||!node.nodeValue)return;"
"var text=node.nodeValue,re=/\\[sound:([^\\]]+)\\]/g,m,last=0,frag=null;"
"while((m=re.exec(text))!==null){"
"if(!frag)frag=document.createDocumentFragment();"
"if(m.index>last)frag.appendChild(document.createTextNode(text.substring(last,m.index)));"
"var src=m[1],a=document.createElement('a');sounds.push(src);"
"a.href='#';a.className='kanki-audio-link';a.setAttribute('data-src',src);a.setAttribute('title','Play audio');"
"a.appendChild(document.createTextNode('\\u25B6'));"
"a.onclick=function(){ping('play',this.getAttribute('data-src'));return false;};frag.appendChild(a);"
"last=re.lastIndex;"
"}"
"if(frag){if(last<text.length)frag.appendChild(document.createTextNode(text.substring(last)));node.parentNode.replaceChild(frag,node);}"
"}"
"function walk(node,sounds){"
"if(!node)return;"
"if(node.nodeType===3){replaceSoundText(node,sounds);return;}"
"if(node.nodeType!==1)return;"
"var tag=(node.tagName||'').toLowerCase();if(tag==='script'||tag==='style'||tag==='textarea')return;"
"var c=node.firstChild;while(c){var n=c.nextSibling;walk(c,sounds);c=n;}"
"}"
"function scan(){try{addStyle();if(!document.body)return;var sounds=[];walk(document.body,sounds);"
"if(sounds.length){setTimeout(function(){ping('play',sounds[0]);},120);}}catch(e){}}"
"if(document.addEventListener)document.addEventListener('DOMContentLoaded',scan,false);"
"else if(window.attachEvent)window.attachEvent('onload',scan);else window.onload=scan;"
"})();</script>";

static char *inject_shim(const char *content)
{
    const char *head;
    size_t content_len, shim_len, prefix_len;
    char *out;

    if (!content) return NULL;
    if (k_strstr(content, "__kankiAudioPing") != NULL) return NULL;

    content_len = k_strlen(content);
    shim_len = sizeof(kanki_audio_shim) - 1;
    head = k_strstr(content, "</head>");
    prefix_len = head ? (size_t)(head - content) : 0;

    out = (char *)malloc(content_len + shim_len + 1);
    if (!out) return NULL;

    if (head) {
        k_memcpy(out, content, prefix_len);
        k_memcpy(out + prefix_len, kanki_audio_shim, shim_len);
        k_memcpy(out + prefix_len + shim_len, head, content_len - prefix_len + 1);
    } else {
        k_memcpy(out, kanki_audio_shim, shim_len);
        k_memcpy(out + shim_len, content, content_len + 1);
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

void webkit_web_view_set_zoom_level(void *web_view, float zoom_level)
{
    static set_zoom_fn real_fn = NULL;
    if (!real_fn) {
        real_fn = (set_zoom_fn)dlsym(RTLD_NEXT, "webkit_web_view_set_zoom_level");
        if (!real_fn) return;
    }

    /* Ranki's default scale=1.5 is multiplied by width/600.  PW6-class screens
     * therefore exceed 3x.  Cap only oversized values, preserving smaller
     * custom zoom levels chosen by users. */
    if (zoom_level > 1.25f) zoom_level = 1.25f;
    real_fn(web_view, zoom_level);
}
