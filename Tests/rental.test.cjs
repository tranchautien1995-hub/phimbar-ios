const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function setup(){
  let events={},rentCount=0,monthCount=0,offers=[];
  const node=(text='')=>({textContent:text,style:{},disabled:false,parentElement:null,contains(n){return n===this||n?.parentElement===this},closest(){return this}});
  const rental=node(),monthly=node(),root=node(),rentTitle=node('Thuê lẻ từng tập phim'),monthTitle=node('Trọn gói'),price=node('800 đ'),term=node('Có giá trị 10 ngày'),buy=node('Chọn'),months=node('Chọn'),form=node();
  rental.parentElement=monthly.parentElement=root;rentTitle.parentElement=buy.parentElement=rental;monthTitle.parentElement=months.parentElement=form.parentElement=monthly;
  rental.querySelector=q=>q==='h2'?price:q==='li'?term:q==='button'?buy:null;
  function dispatch(target,type){let e={target,prevented:false,preventDefault(){this.prevented=true},stopImmediatePropagation(){this.prevented=true}};for(const cb of events[type]||[])cb(e);return e.prevented;}
  buy.click=()=>{if(!dispatch(buy,'click'))rentCount++};months.click=()=>{if(!dispatch(months,'click'))monthCount++};
  const document={title:'Phim A · Tập 2',querySelectorAll:q=>q==='h3'?[rentTitle,monthTitle]:q==='button'?[buy,months]:[],querySelector:q=>q.includes('h1')?node('Phim A · Tập 2'):null,addEventListener:(type,cb)=>(events[type]??=[]).push(cb)};
  const location={pathname:'/watch/episode-2',href:'https://phimbar.com/watch/episode-2'};
  const window={webkit:{messageHandlers:{rental:{postMessage:v=>offers.push(v)}}}};
  const context={document,window,location,navigator:{userAgent:'Fixture'},console};vm.runInNewContext(fs.readFileSync('Resources/rental.js','utf8'),context);
  return {api:window.XemRental,price,buy,months,monthly,offers,location,dispatch,form,counts:()=>({rentCount,monthCount})};
}
test('opening rental never charges and hides month card',()=>{let f=setup();assert.equal(f.api.prepare(),'open');assert.equal(f.monthly.style.display,'none');assert.deepEqual(f.counts(),{rentCount:0,monthCount:0})});
test('site rental click requires native confirmation',()=>{let f=setup();f.buy.click();assert.equal(f.offers.length,1);assert.equal(f.offers[0].price,'800 đ');assert.equal(f.counts().rentCount,0)});
test('confirmed rental charges only exact rental once',()=>{let f=setup(),o=f.api.offer();assert.equal(f.api.commit(o.fingerprint),true);assert.equal(f.api.commit(o.fingerprint),false);assert.deepEqual(f.counts(),{rentCount:1,monthCount:0})});
test('changed price or episode invalidates confirmation',()=>{let f=setup(),o=f.api.offer();f.price.textContent='900 đ';assert.equal(f.api.commit(o.fingerprint),false);f.price.textContent='800 đ';f.location.pathname='/watch/episode-3';assert.equal(f.api.commit(o.fingerprint),false);assert.equal(f.counts().rentCount,0)});
test('monthly click and submit are blocked',()=>{let f=setup();f.months.click();assert.equal(f.dispatch(f.form,'submit'),true);assert.equal(f.counts().monthCount,0)});
test('login and other pages cannot issue rental offers',()=>{let f=setup();f.location.pathname='/auth/login';assert.equal(f.api.offer(),null)});
test('no source URL is invented when website has no video',()=>{let f=setup();assert.equal(f.api.snapshot().urls.length,0)});
