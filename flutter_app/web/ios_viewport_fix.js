// iPhone home-screen app only: after the keyboard closes, iOS can leave the page shrunk or
// shifted, so the bottom bar sits above a dead band (flutter/flutter#111896). When that
// happens, flipping the app's display makes WebKit measure the screen again.
(function () {
  if (navigator.standalone !== true) return;
  var tallest = window.innerHeight;
  window.addEventListener('resize', function () { tallest = Math.max(tallest, window.innerHeight); });
  window.addEventListener('orientationchange', function () { tallest = 0; });
  document.addEventListener('focusout', function (e) {
    var t = e.target;
    if (!t || (t.tagName !== 'INPUT' && t.tagName !== 'TEXTAREA')) return;
    setTimeout(function () {
      var active = document.activeElement;
      if (active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA')) return; // still typing
      if (window.visualViewport && window.visualViewport.offsetTop !== 0) window.scrollTo(0, 0);
      var view = document.querySelector('flutter-view');
      if (!view || tallest - window.innerHeight <= 4) return;
      view.style.display = 'none';
      void view.offsetHeight; // synchronous reflow
      view.style.display = '';
      window.dispatchEvent(new Event('resize')); // let Flutter re-read the size
    }, 150);
  }, true);
})();
