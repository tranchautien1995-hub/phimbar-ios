(function(){
  'use strict';
  if(!Object.hasOwn)Object.hasOwn=function(o,p){return Object.prototype.hasOwnProperty.call(o,p);};
  if(!Array.prototype.at)Object.defineProperty(Array.prototype,'at',{value:function(i){i=Math.trunc(Number(i)||0);return this[i<0?this.length+i:i];},configurable:true,writable:true});
  if(!String.prototype.at)Object.defineProperty(String.prototype,'at',{value:function(i){i=Math.trunc(Number(i)||0);return this[i<0?this.length+i:i];},configurable:true,writable:true});
  function apply(){if(!document.head)return;var style=document.getElementById('phimbar-ios-legacy');if(!style){style=document.createElement('style');style.id='phimbar-ios-legacy';document.head.appendChild(style);}style.textContent=window.__phimbarLegacyCSS||'';}
  window.PhimbarCompat={apply:apply};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();
