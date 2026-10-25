// Headword typeahead in the navbar search box (Bootstrap 2 typeahead).
//
// Matching ignores accents and case and works on the start of the headword,
// like the server-side search. Picking a suggestion opens that entry; pressing
// Enter without picking one searches for what was typed.
$(function () {
  var $box = $('.typeahead');
  var $form = $box.closest('form');

  // Mirrors Dictionary.headword_key on the server.
  function key(s) {
    return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
      .replace(/[¹²³⁰-⁹()]/g, '')
      .replace(/^[?\s]*\d+\??(?:,\s*\d+)*\s+/, '')
      .replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  }

  $.getJSON('/headwords.json', function (rows) {
    var labels = [], byLabel = {};
    $.each(rows, function (_, row) {
      // Disambiguate the rare identical labels so each maps to one entry.
      var label = row[0], n = 2;
      while (byLabel[label]) { label = row[0] + ' (' + n++ + ')'; }
      labels.push(label);
      byLabel[label] = { key: row[1], id: row[2], order: labels.length };
    });

    $box.typeahead({
      source: labels,
      items: 10,
      matcher: function (item) {
        var q = key(this.query);
        return q.length > 0 && byLabel[item].key.indexOf(q) === 0;
      },
      sorter: function (items) {
        var q = key(this.query);
        return items.sort(function (a, b) {
          var A = byLabel[a], B = byLabel[b];
          var exact = (B.key === q) - (A.key === q);
          return exact || A.key.length - B.key.length || A.order - B.order;
        });
      },
      // The stock highlighter builds a regex from the raw query.
      highlighter: function (item) { return $('<div>').text(item).html(); },
      updater: function (item) {
        window.location = '/entries/' + byLabel[item].id;
        return item;
      }
    });

    var ta = $box.data('typeahead');
    // Don't preselect the first suggestion, so Enter searches the typed text.
    var render = ta.render;
    ta.render = function (items) {
      render.call(this, items);
      this.$menu.find('.active').removeClass('active');
      return this;
    };
    var select = ta.select;
    ta.select = function () {
      if (this.$menu.find('.active').length) { return select.call(this); }
      this.hide();
      $form.submit();
      return this;
    };

    // Bootstrap 2 only looks up on keyup; also react to paste/IME/autofill.
    $box.on('input', function () { ta.lookup(); });
  });

  // Scroll a highlighted line into view when arriving from an entry.
  var $hl = $('li.highlight');
  if ($hl.length) { $('html, body').scrollTop($hl.offset().top - 120); }
});
