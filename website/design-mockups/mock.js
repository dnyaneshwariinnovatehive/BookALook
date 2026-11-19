
// Decorative QR-looking pattern for the mockup only.
document.querySelectorAll('.qr').forEach(function(el, n){
  var s=21, seed=7+n*13, h='<svg viewBox="0 0 '+s+' '+s+'" width="100%" height="100%" shape-rendering="crispEdges">';
  function rnd(){seed=(seed*9301+49297)%233280;return seed/233280}
  function finder(x,y){return x>=0&&x<7&&y>=0&&y<7}
  for(var y=0;y<s;y++)for(var x=0;x<s;x++){
    var f=[[0,0],[s-7,0],[0,s-7]].map(function(o){var a=x-o[0],b=y-o[1];if(a<0||a>6||b<0||b>6)return null;return (a==0||a==6||b==0||b==6||(a>1&&a<5&&b>1&&b<5))});
    var on=f.filter(function(v){return v!==null});
    var fill=on.length?on[0]:rnd()>.52;
    if(fill)h+='<rect x="'+x+'" y="'+y+'" width="1" height="1" fill="#18151D"/>';
  }
  el.innerHTML=h+'</svg>';
});
window.addEventListener('load',function(){var o=[].map.call(document.querySelectorAll('[data-cut]'),function(e){return e.dataset.cut+':'+Math.round(e.getBoundingClientRect().top+scrollY)});var t='W'+innerWidth+'|H'+document.documentElement.scrollHeight+'|'+o.join(',');document.title=t;if(parent!==window)parent.postMessage(t,'*')});
