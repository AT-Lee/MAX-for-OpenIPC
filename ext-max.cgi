#!/usr/bin/haserl
<%in p/common.cgi %>
<%
page_title="MAX"
config_file=/etc/webui/max.conf
params="enabled token chat_id caption video_duration min_free_pct proxy interval crontab"

if [ "$GET_send" = "test" ]; then
        echo "Content-type: text/html; charset=UTF-8"; echo
        /usr/sbin/max >/dev/null 2>&1 && echo OK || echo FAIL
        exit 0
fi

if [ "$REQUEST_METHOD" = "POST" ]; then
        for p in $params; do eval max_${p}=\$POST_max_${p}; done
        [ "$max_enabled" = "true" ] && {
                [ -z "$max_token" ] && set_error_flag "Token required."
                [ -z "$max_chat_id" ] && set_error_flag "Chat ID required."
        }
        case "$max_video_duration" in *[!0-9]*) max_video_duration="10" ;; esac
        case "$max_min_free_pct" in *[!0-9]*) max_min_free_pct="10" ;; esac
        if [ -z "$error" ]; then
                rm -f "$config_file"
                for p in $params; do echo "max_${p}=\"$(eval echo \$max_${p})\"" >> "$config_file"; done
                sed -i /max/d /etc/crontabs/root
                [ "$max_enabled" = "true" ] && [ "$max_crontab" = "true" ] && \
                        echo "*/${max_interval} * * * * /usr/sbin/max" >> /etc/crontabs/root
                redirect_back "success" "MAX config updated."
        fi
        redirect_to "$SCRIPT_NAME"
fi

[ -e "$config_file" ] && include $config_file
[ -z "$max_crontab" ] && max_crontab="true"
[ -z "$max_interval" ] && max_interval="15"
[ -z "$max_caption" ] && max_caption="%hostname, %datetime"
[ -z "$max_video_duration" ] && max_video_duration="10"
[ -z "$max_min_free_pct" ] && max_min_free_pct="10"

maj_warn=""
if [ -e /etc/majestic.yaml ]; then
        maj_hls=$(awk '/^hls:/{h=1;next} /^[a-zA-Z]+:/{h=0} h&&/enabled:/{print $2; exit}' /etc/majestic.yaml | tr -d '"' | tr -d "'")
        [ "$maj_hls" != "true" ] && \
                maj_warn="<div class=\"alert alert-warning small mb-3\"><b>Majestic not ready.</b> Enable <code>hls</code> in <code>/etc/majestic.yaml</code>:<pre class=\"mb-1 mt-2\">hls:\n  enabled: true</pre>then <code>/etc/init.d/S95majestic restart</code>.</div>"
else
        maj_warn="<div class=\"alert alert-warning small mb-3\"><code>/etc/majestic.yaml</code> not found.</div>"
fi
%>
<%in p/header.cgi %>
<div class="row g-4">
<div class="col-12 col-lg-8"><div class="card h-100"><div class="card-body">
<h3>MAX</h3>
<p class="small text-secondary">Post video clips to MAX. Each motion event captures one segment; if motion continues, additional segments are captured and sent as separate messages.</p>
<%= $maj_warn %>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "max_enabled" "Enable MAX" "eval" %>
<div class="text-uppercase x-small text-secondary mt-3 mb-2">Bot</div>
<% field_text "max_token" "Token" "Bot auth token." %>
<% field_text "max_chat_id" "Chat ID" "Chat to post videos to." %>
<div class="text-uppercase x-small text-secondary mt-3 mb-2">Video</div>
<% field_string "max_video_duration" "Segment duration" "eval" "5 10 15 30" "Seconds per segment. Motion extends capture." %>
<% field_string "max_min_free_pct" "Min free %" "eval" "5 10 15 20" "Abort when /tmp free space below this %." %>
<% field_text "max_caption" "Caption" "Supports %hostname, %datetime, %soctemp." %>
<div class="text-uppercase x-small text-secondary mt-3 mb-2">Schedule</div>
<% field_string "max_interval" "Interval" "eval" "15 30 60 120" "Minutes." %>
<% field_switch "max_crontab" "Add to crontab" "eval" "Send videos timed by interval." %>
<div class="text-uppercase x-small text-secondary mt-3 mb-2">Options</div>
<% field_switch "max_proxy" "Use SOCKS5" "eval" "<a href=\"ext-proxy.cgi\">Configure proxy.</a>" %>
<% button_submit %>
</form></div></div></div>
<div class="col-12 col-lg-4"><div class="card h-100"><div class="card-body">
<h3>Test</h3>
<button type="button" id="b" class="btn btn-sm btn-outline-secondary">Send test video</button>
<span id="s" class="small ms-2"></span>
<hr class="my-3">
<dl class="small list mb-0"><dt>Webhook</dt>
<dd class="text-break cp2cb">http://root:12345@<%= $network_address %>/cgi-bin/ext-max.cgi?send=test</dd></dl>
</div></div></div>
</div>
<script>document.getElementById('b').onclick=function(){var s=document.getElementById('s');s.textContent='...';s.className='small ms-2 text-secondary';fetch('?send=test').then(r=>r.text()).then(t=>{t=t.trim();s.textContent=t==='OK'?'sent':'failed';s.className='small ms-2 '+(t==='OK'?'text-success':'text-danger');}).catch(()=>{s.textContent='err';s.className='small ms-2 text-danger';});};</script>
<%in p/footer.cgi %>
