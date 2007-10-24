// script.aculo.us builder.js v1.7.1_beta3, Fri May 25 17:19:41 +0200 2007

// Copyright (c) 2005-2007 Thomas Fuchs (http://script.aculo.us, http://mir.aculo.us)
//
// script.aculo.us is freely distributable under the terms of an MIT-style license.
// For details, see the script.aculo.us web site: http://script.aculo.us/

var Builder = {
  NODEMAP: {
    AREA: 'map',
    CAPTION: 'table',
    COL: 'table',
    COLGROUP: 'table',
    LEGEND: 'fieldset',
    OPTGROUP: 'select',
    OPTION: 'select',
    PARAM: 'object',
    TBODY: 'table',
    TD: 'table',
    TFOOT: 'table',
    TH: 'table',
    THEAD: 'table',
    TR: 'table'
  },
  // note: For Firefox < 1.5, OPTION and OPTGROUP tags are currently broken,
  //       due to a Firefox bug
  node: function(elementName) {
    elementName = elementName.toUpperCase();
    
    // try innerHTML approach
    var parentTag = this.NODEMAP[elementName] || 'div';
    var parentElement = document.createElement(parentTag);
    try { // prevent IE "feature": http://dev.rubyonrails.org/ticket/2707
      parentElement.innerHTML = "<" + elementName + "></" + elementName + ">";
    } catch(e) {}
    var element = parentElement.firstChild || null;
      
    // see if browser added wrapping tags
    if(element && (element.tagName.toUpperCase() != elementName))
      element = element.getElementsByTagName(elementName)[0];
    
    // fallback to createElement approach
    if(!element) element = document.createElement(elementName);
    
    // abort if nothing could be created
    if(!element) return;

    // attributes (or text)
    if(arguments[1])
      if(this._isStringOrNumber(arguments[1]) ||
        (arguments[1] instanceof Array) ||
        arguments[1].tagName) {
          this._children(element, arguments[1]);
        } else {
          var attrs = this._attributes(arguments[1]);
          if(attrs.length) {
            try { // prevent IE "feature": http://dev.rubyonrails.org/ticket/2707
              parentElement.innerHTML = "<" +elementName + " " +
                attrs + "></" + elementName + ">";
            } catch(e) {}
            element = parentElement.firstChild || null;
            // workaround firefox 1.0.X bug
            if(!element) {
              element = document.createElement(elementName);
              for(attr in arguments[1]) 
                element[attr == 'class' ? 'className' : attr] = arguments[1][attr];
            }
            if(element.tagName.toUpperCase() != elementName)
              element = parentElement.getElementsByTagName(elementName)[0];
          }
        } 

    // text, or array of children
    if(arguments[2])
      this._children(element, arguments[2]);

     return element;
  },
  _text: function(text) {
     return document.createTextNode(text);
  },

  ATTR_MAP: {
    'className': 'class',
    'htmlFor': 'for'
  },

  _attributes: function(attributes) {
    var attrs = [];
    for(attribute in attributes)
      attrs.push((attribute in this.ATTR_MAP ? this.ATTR_MAP[attribute] : attribute) +
          '="' + attributes[attribute].toString().escapeHTML().gsub(/"/,'&quot;') + '"');
    return attrs.join(" ");
  },
  _children: function(element, children) {
    if(children.tagName) {
      element.appendChild(children);
      return;
    }
    if(typeof children=='object') { // array can hold nodes and text
      children.flatten().each( function(e) {
        if(typeof e=='object')
          element.appendChild(e)
        else
          if(Builder._isStringOrNumber(e))
            element.appendChild(Builder._text(e));
      });
    } else
      if(Builder._isStringOrNumber(children))
        element.appendChild(Builder._text(children));
  },
  _isStringOrNumber: function(param) {
    return(typeof param=='string' || typeof param=='number');
  },
  build: function(html) {
    var element = this.node('div');
    $(element).update(html.strip());
    return element.down();
  },
  dump: function(scope) { 
    if(typeof scope != 'object' && typeof scope != 'function') scope = window; //global scope 
  
    var tags = ("A ABBR ACRONYM ADDRESS APPLET AREA B BASE BASEFONT BDO BIG BLOCKQUOTE BODY " +
      "BR BUTTON CAPTION CENTER CITE CODE COL COLGROUP DD DEL DFN DIR DIV DL DT EM FIELDSET " +
      "FONT FORM FRAME FRAMESET H1 H2 H3 H4 H5 H6 HEAD HR HTML I IFRAME IMG INPUT INS ISINDEX "+
      "KBD LABEL LEGEND LI LINK MAP MENU META NOFRAMES NOSCRIPT OBJECT OL OPTGROUP OPTION P "+
      "PARAM PRE Q S SAMP SCRIPT SELECT SMALL SPAN STRIKE STRONG STYLE SUB SUP TABLE TBODY TD "+
      "TEXTAREA TFOOT TH THEAD TITLE TR TT U UL VAR").split(/\s+/);
  
    tags.each( function(tag){ 
      scope[tag] = function() { 
        return Builder.node.apply(Builder, [tag].concat($A(arguments)));  
      } 
    });
  }
}
// script.aculo.us effects.js v1.7.1_beta3, Fri May 25 17:19:41 +0200 2007

// Copyright (c) 2005-2007 Thomas Fuchs (http://script.aculo.us, http://mir.aculo.us)
// Contributors:
//  Justin Palmer (http://encytemedia.com/)
//  Mark Pilgrim (http://diveintomark.org/)
//  Martin Bialasinki
// 
// script.aculo.us is freely distributable under the terms of an MIT-style license.
// For details, see the script.aculo.us web site: http://script.aculo.us/ 

// converts rgb() and #xxx to #xxxxxx format,  
// returns self (or first argument) if not convertable  
String.prototype.parseColor = function() {  
  var color = '#';
  if(this.slice(0,4) == 'rgb(') {  
    var cols = this.slice(4,this.length-1).split(',');  
    var i=0; do { color += parseInt(cols[i]).toColorPart() } while (++i<3);  
  } else {  
    if(this.slice(0,1) == '#') {  
      if(this.length==4) for(var i=1;i<4;i++) color += (this.charAt(i) + this.charAt(i)).toLowerCase();  
      if(this.length==7) color = this.toLowerCase();  
    }  
  }  
  return(color.length==7 ? color : (arguments[0] || this));  
}

/*--------------------------------------------------------------------------*/

Element.collectTextNodes = function(element) {  
  return $A($(element).childNodes).collect( function(node) {
    return (node.nodeType==3 ? node.nodeValue : 
      (node.hasChildNodes() ? Element.collectTextNodes(node) : ''));
  }).flatten().join('');
}

Element.collectTextNodesIgnoreClass = function(element, className) {  
  return $A($(element).childNodes).collect( function(node) {
    return (node.nodeType==3 ? node.nodeValue : 
      ((node.hasChildNodes() && !Element.hasClassName(node,className)) ? 
        Element.collectTextNodesIgnoreClass(node, className) : ''));
  }).flatten().join('');
}

Element.setContentZoom = function(element, percent) {
  element = $(element);  
  element.setStyle({fontSize: (percent/100) + 'em'});   
  if(Prototype.Browser.WebKit) window.scrollBy(0,0);
  return element;
}

Element.getInlineOpacity = function(element){
  return $(element).style.opacity || '';
}

Element.forceRerendering = function(element) {
  try {
    element = $(element);
    var n = document.createTextNode(' ');
    element.appendChild(n);
    element.removeChild(n);
  } catch(e) { }
};

/*--------------------------------------------------------------------------*/

Array.prototype.call = function() {
  var args = arguments;
  this.each(function(f){ f.apply(this, args) });
}

/*--------------------------------------------------------------------------*/

var Effect = {
  _elementDoesNotExistError: {
    name: 'ElementDoesNotExistError',
    message: 'The specified DOM element does not exist, but is required for this effect to operate'
  },
  tagifyText: function(element) {
    if(typeof Builder == 'undefined')
      throw("Effect.tagifyText requires including script.aculo.us' builder.js library");
      
    var tagifyStyle = 'position:relative';
    if(Prototype.Browser.IE) tagifyStyle += ';zoom:1';
    
    element = $(element);
    $A(element.childNodes).each( function(child) {
      if(child.nodeType==3) {
        child.nodeValue.toArray().each( function(character) {
          element.insertBefore(
            Builder.node('span',{style: tagifyStyle},
              character == ' ' ? String.fromCharCode(160) : character), 
              child);
        });
        Element.remove(child);
      }
    });
  },
  multiple: function(element, effect) {
    var elements;
    if(((typeof element == 'object') || 
        (typeof element == 'function')) && 
       (element.length))
      elements = element;
    else
      elements = $(element).childNodes;
      
    var options = Object.extend({
      speed: 0.1,
      delay: 0.0
    }, arguments[2] || {});
    var masterDelay = options.delay;

    $A(elements).each( function(element, index) {
      new effect(element, Object.extend(options, { delay: index * options.speed + masterDelay }));
    });
  },
  PAIRS: {
    'slide':  ['SlideDown','SlideUp'],
    'blind':  ['BlindDown','BlindUp'],
    'appear': ['Appear','Fade']
  },
  toggle: function(element, effect) {
    element = $(element);
    effect = (effect || 'appear').toLowerCase();
    var options = Object.extend({
      queue: { position:'end', scope:(element.id || 'global'), limit: 1 }
    }, arguments[2] || {});
    Effect[element.visible() ? 
      Effect.PAIRS[effect][1] : Effect.PAIRS[effect][0]](element, options);
  }
};

var Effect2 = Effect; // deprecated

/* ------------- transitions ------------- */

Effect.Transitions = {
  linear: Prototype.K,
  sinoidal: function(pos) {
    return (-Math.cos(pos*Math.PI)/2) + 0.5;
  },
  reverse: function(pos) {
    return 1-pos;
  },
  flicker: function(pos) {
    var pos = ((-Math.cos(pos*Math.PI)/4) + 0.75) + Math.random()/4;
    return (pos > 1 ? 1 : pos);
  },
  wobble: function(pos) {
    return (-Math.cos(pos*Math.PI*(9*pos))/2) + 0.5;
  },
  pulse: function(pos, pulses) { 
    pulses = pulses || 5; 
    return (
      Math.round((pos % (1/pulses)) * pulses) == 0 ? 
            ((pos * pulses * 2) - Math.floor(pos * pulses * 2)) : 
        1 - ((pos * pulses * 2) - Math.floor(pos * pulses * 2))
      );
  },
  none: function(pos) {
    return 0;
  },
  full: function(pos) {
    return 1;
  }
};

/* ------------- core effects ------------- */

Effect.ScopedQueue = Class.create();
Object.extend(Object.extend(Effect.ScopedQueue.prototype, Enumerable), {
  initialize: function() {
    this.effects  = [];
    this.interval = null;    
  },
  _each: function(iterator) {
    this.effects._each(iterator);
  },
  add: function(effect) {
    var timestamp = new Date().getTime();
    
    var position = (typeof effect.options.queue == 'string') ? 
      effect.options.queue : effect.options.queue.position;
    
    switch(position) {
      case 'front':
        // move unstarted effects after this effect  
        this.effects.findAll(function(e){ return e.state=='idle' }).each( function(e) {
            e.startOn  += effect.finishOn;
            e.finishOn += effect.finishOn;
          });
        break;
      case 'with-last':
        timestamp = this.effects.pluck('startOn').max() || timestamp;
        break;
      case 'end':
        // start effect after last queued effect has finished
        timestamp = this.effects.pluck('finishOn').max() || timestamp;
        break;
    }
    
    effect.startOn  += timestamp;
    effect.finishOn += timestamp;

    if(!effect.options.queue.limit || (this.effects.length < effect.options.queue.limit))
      this.effects.push(effect);
    
    if(!this.interval)
      this.interval = setInterval(this.loop.bind(this), 15);
  },
  remove: function(effect) {
    this.effects = this.effects.reject(function(e) { return e==effect });
    if(this.effects.length == 0) {
      clearInterval(this.interval);
      this.interval = null;
    }
  },
  loop: function() {
    var timePos = new Date().getTime();
    for(var i=0, len=this.effects.length;i<len;i++) 
      this.effects[i] && this.effects[i].loop(timePos);
  }
});

Effect.Queues = {
  instances: $H(),
  get: function(queueName) {
    if(typeof queueName != 'string') return queueName;
    
    if(!this.instances[queueName])
      this.instances[queueName] = new Effect.ScopedQueue();
      
    return this.instances[queueName];
  }
}
Effect.Queue = Effect.Queues.get('global');

Effect.DefaultOptions = {
  transition: Effect.Transitions.sinoidal,
  duration:   1.0,   // seconds
  fps:        100,   // 100= assume 66fps max.
  sync:       false, // true for combining
  from:       0.0,
  to:         1.0,
  delay:      0.0,
  queue:      'parallel'
}

Effect.Base = function() {};
Effect.Base.prototype = {
  position: null,
  start: function(options) {
    function codeForEvent(options,eventName){
      return (
        (options[eventName+'Internal'] ? 'this.options.'+eventName+'Internal(this);' : '') +
        (options[eventName] ? 'this.options.'+eventName+'(this);' : '')
      );
    }
    if(options.transition === false) options.transition = Effect.Transitions.linear;
    this.options      = Object.extend(Object.extend({},Effect.DefaultOptions), options || {});
    this.currentFrame = 0;
    this.state        = 'idle';
    this.startOn      = this.options.delay*1000;
    this.finishOn     = this.startOn+(this.options.duration*1000);
    this.fromToDelta  = this.options.to-this.options.from;
    this.totalTime    = this.finishOn-this.startOn;
    this.totalFrames  = this.options.fps*this.options.duration;
    
    eval('this.render = function(pos){ '+
      'if(this.state=="idle"){this.state="running";'+
      codeForEvent(options,'beforeSetup')+
      (this.setup ? 'this.setup();':'')+ 
      codeForEvent(options,'afterSetup')+
      '};if(this.state=="running"){'+
      'pos=this.options.transition(pos)*'+this.fromToDelta+'+'+this.options.from+';'+
      'this.position=pos;'+
      codeForEvent(options,'beforeUpdate')+
      (this.update ? 'this.update(pos);':'')+
      codeForEvent(options,'afterUpdate')+
      '}}');
    
    this.event('beforeStart');
    if(!this.options.sync)
      Effect.Queues.get(typeof this.options.queue == 'string' ? 
        'global' : this.options.queue.scope).add(this);
  },
  loop: function(timePos) {
    if(timePos >= this.startOn) {
      if(timePos >= this.finishOn) {
        this.render(1.0);
        this.cancel();
        this.event('beforeFinish');
        if(this.finish) this.finish(); 
        this.event('afterFinish');
        return;  
      }
      var pos   = (timePos - this.startOn) / this.totalTime,
          frame = Math.round(pos * this.totalFrames);
      if(frame > this.currentFrame) {
        this.render(pos);
        this.currentFrame = frame;
      }
    }
  },
  cancel: function() {
    if(!this.options.sync)
      Effect.Queues.get(typeof this.options.queue == 'string' ? 
        'global' : this.options.queue.scope).remove(this);
    this.state = 'finished';
  },
  event: function(eventName) {
    if(this.options[eventName + 'Internal']) this.options[eventName + 'Internal'](this);
    if(this.options[eventName]) this.options[eventName](this);
  },
  inspect: function() {
    var data = $H();
    for(property in this)
      if(typeof this[property] != 'function') data[property] = this[property];
    return '#<Effect:' + data.inspect() + ',options:' + $H(this.options).inspect() + '>';
  }
}

Effect.Parallel = Class.create();
Object.extend(Object.extend(Effect.Parallel.prototype, Effect.Base.prototype), {
  initialize: function(effects) {
    this.effects = effects || [];
    this.start(arguments[1]);
  },
  update: function(position) {
    this.effects.invoke('render', position);
  },
  finish: function(position) {
    this.effects.each( function(effect) {
      effect.render(1.0);
      effect.cancel();
      effect.event('beforeFinish');
      if(effect.finish) effect.finish(position);
      effect.event('afterFinish');
    });
  }
});

Effect.Event = Class.create();
Object.extend(Object.extend(Effect.Event.prototype, Effect.Base.prototype), {
  initialize: function() {
    var options = Object.extend({
      duration: 0
    }, arguments[0] || {});
    this.start(options);
  },
  update: Prototype.emptyFunction
});

Effect.Opacity = Class.create();
Object.extend(Object.extend(Effect.Opacity.prototype, Effect.Base.prototype), {
  initialize: function(element) {
    this.element = $(element);
    if(!this.element) throw(Effect._elementDoesNotExistError);
    // make this work on IE on elements without 'layout'
    if(Prototype.Browser.IE && (!this.element.currentStyle.hasLayout))
      this.element.setStyle({zoom: 1});
    var options = Object.extend({
      from: this.element.getOpacity() || 0.0,
      to:   1.0
    }, arguments[1] || {});
    this.start(options);
  },
  update: function(position) {
    this.element.setOpacity(position);
  }
});

Effect.Move = Class.create();
Object.extend(Object.extend(Effect.Move.prototype, Effect.Base.prototype), {
  initialize: function(element) {
    this.element = $(element);
    if(!this.element) throw(Effect._elementDoesNotExistError);
    var options = Object.extend({
      x:    0,
      y:    0,
      mode: 'relative'
    }, arguments[1] || {});
    this.start(options);
  },
  setup: function() {
    // Bug in Opera: Opera returns the "real" position of a static element or
    // relative element that does not have top/left explicitly set.
    // ==> Always set top and left for position relative elements in your stylesheets 
    // (to 0 if you do not need them) 
    this.element.makePositioned();
    this.originalLeft = parseFloat(this.element.getStyle('left') || '0');
    this.originalTop  = parseFloat(this.element.getStyle('top')  || '0');
    if(this.options.mode == 'absolute') {
      // absolute movement, so we need to calc deltaX and deltaY
      this.options.x = this.options.x - this.originalLeft;
      this.options.y = this.options.y - this.originalTop;
    }
  },
  update: function(position) {
    this.element.setStyle({
      left: Math.round(this.options.x  * position + this.originalLeft) + 'px',
      top:  Math.round(this.options.y  * position + this.originalTop)  + 'px'
    });
  }
});

// for backwards compatibility
Effect.MoveBy = function(element, toTop, toLeft) {
  return new Effect.Move(element, 
    Object.extend({ x: toLeft, y: toTop }, arguments[3] || {}));
};

Effect.Scale = Class.create();
Object.extend(Object.extend(Effect.Scale.prototype, Effect.Base.prototype), {
  initialize: function(element, percent) {
    this.element = $(element);
    if(!this.element) throw(Effect._elementDoesNotExistError);
    var options = Object.extend({
      scaleX: true,
      scaleY: true,
      scaleContent: true,
      scaleFromCenter: false,
      scaleMode: 'box',        // 'box' or 'contents' or {} with provided values
      scaleFrom: 100.0,
      scaleTo:   percent
    }, arguments[2] || {});
    this.start(options);
  },
  setup: function() {
    this.restoreAfterFinish = this.options.restoreAfterFinish || false;
    this.elementPositioning = this.element.getStyle('position');
    
    this.originalStyle = {};
    ['top','left','width','height','fontSize'].each( function(k) {
      this.originalStyle[k] = this.element.style[k];
    }.bind(this));
      
    this.originalTop  = this.element.offsetTop;
    this.originalLeft = this.element.offsetLeft;
    
    var fontSize = this.element.getStyle('font-size') || '100%';
    ['em','px','%','pt'].each( function(fontSizeType) {
      if(fontSize.indexOf(fontSizeType)>0) {
        this.fontSize     = parseFloat(fontSize);
        this.fontSizeType = fontSizeType;
      }
    }.bind(this));
    
    this.factor = (this.options.scaleTo - this.options.scaleFrom)/100;
    
    this.dims = null;
    if(this.options.scaleMode=='box')
      this.dims = [this.element.offsetHeight, this.element.offsetWidth];
    if(/^content/.test(this.options.scaleMode))
      this.dims = [this.element.scrollHeight, this.element.scrollWidth];
    if(!this.dims)
      this.dims = [this.options.scaleMode.originalHeight,
                   this.options.scaleMode.originalWidth];
  },
  update: function(position) {
    var currentScale = (this.options.scaleFrom/100.0) + (this.factor * position);
    if(this.options.scaleContent && this.fontSize)
      this.element.setStyle({fontSize: this.fontSize * currentScale + this.fontSizeType });
    this.setDimensions(this.dims[0] * currentScale, this.dims[1] * currentScale);
  },
  finish: function(position) {
    if(this.restoreAfterFinish) this.element.setStyle(this.originalStyle);
  },
  setDimensions: function(height, width) {
    var d = {};
    if(this.options.scaleX) d.width = Math.round(width) + 'px';
    if(this.options.scaleY) d.height = Math.round(height) + 'px';
    if(this.options.scaleFromCenter) {
      var topd  = (height - this.dims[0])/2;
      var leftd = (width  - this.dims[1])/2;
      if(this.elementPositioning == 'absolute') {
        if(this.options.scaleY) d.top = this.originalTop-topd + 'px';
        if(this.options.scaleX) d.left = this.originalLeft-leftd + 'px';
      } else {
        if(this.options.scaleY) d.top = -topd + 'px';
        if(this.options.scaleX) d.left = -leftd + 'px';
      }
    }
    this.element.setStyle(d);
  }
});

Effect.Highlight = Class.create();
Object.extend(Object.extend(Effect.Highlight.prototype, Effect.Base.prototype), {
  initialize: function(element) {
    this.element = $(element);
    if(!this.element) throw(Effect._elementDoesNotExistError);
    var options = Object.extend({ startcolor: '#ffff99' }, arguments[1] || {});
    this.start(options);
  },
  setup: function() {
    // Prevent executing on elements not in the layout flow
    if(this.element.getStyle('display')=='none') { this.cancel(); return; }
    // Disable background image during the effect
    this.oldStyle = {};
    if (!this.options.keepBackgroundImage) {
      this.oldStyle.backgroundImage = this.element.getStyle('background-image');
      this.element.setStyle({backgroundImage: 'none'});
    }
    if(!this.options.endcolor)
      this.options.endcolor = this.element.getStyle('background-color').parseColor('#ffffff');
    if(!this.options.restorecolor)
      this.options.restorecolor = this.element.getStyle('background-color');
    // init color calculations
    this._base  = $R(0,2).map(function(i){ return parseInt(this.options.startcolor.slice(i*2+1,i*2+3),16) }.bind(this));
    this._delta = $R(0,2).map(function(i){ return parseInt(this.options.endcolor.slice(i*2+1,i*2+3),16)-this._base[i] }.bind(this));
  },
  update: function(position) {
    this.element.setStyle({backgroundColor: $R(0,2).inject('#',function(m,v,i){
      return m+(Math.round(this._base[i]+(this._delta[i]*position)).toColorPart()); }.bind(this)) });
  },
  finish: function() {
    this.element.setStyle(Object.extend(this.oldStyle, {
      backgroundColor: this.options.restorecolor
    }));
  }
});

Effect.ScrollTo = Class.create();
Object.extend(Object.extend(Effect.ScrollTo.prototype, Effect.Base.prototype), {
  initialize: function(element) {
    this.element = $(element);
    this.start(arguments[1] || {});
  },
  setup: function() {
    Position.prepare();
    var offsets = Position.cumulativeOffset(this.element);
    if(this.options.offset) offsets[1] += this.options.offset;
    var max = window.innerHeight ? 
      window.height - window.innerHeight :
      document.body.scrollHeight - 
        (document.documentElement.clientHeight ? 
          document.documentElement.clientHeight : document.body.clientHeight);
    this.scrollStart = Position.deltaY;
    this.delta = (offsets[1] > max ? max : offsets[1]) - this.scrollStart;
  },
  update: function(position) {
    Position.prepare();
    window.scrollTo(Position.deltaX, 
      this.scrollStart + (position*this.delta));
  }
});

/* ------------- combination effects ------------- */

Effect.Fade = function(element) {
  element = $(element);
  var oldOpacity = element.getInlineOpacity();
  var options = Object.extend({
  from: element.getOpacity() || 1.0,
  to:   0.0,
  afterFinishInternal: function(effect) { 
    if(effect.options.to!=0) return;
    effect.element.hide().setStyle({opacity: oldOpacity}); 
  }}, arguments[1] || {});
  return new Effect.Opacity(element,options);
}

Effect.Appear = function(element) {
  element = $(element);
  var options = Object.extend({
  from: (element.getStyle('display') == 'none' ? 0.0 : element.getOpacity() || 0.0),
  to:   1.0,
  // force Safari to render floated elements properly
  afterFinishInternal: function(effect) {
    effect.element.forceRerendering();
  },
  beforeSetup: function(effect) {
    effect.element.setOpacity(effect.options.from).show(); 
  }}, arguments[1] || {});
  return new Effect.Opacity(element,options);
}

Effect.Puff = function(element) {
  element = $(element);
  var oldStyle = { 
    opacity: element.getInlineOpacity(), 
    position: element.getStyle('position'),
    top:  element.style.top,
    left: element.style.left,
    width: element.style.width,
    height: element.style.height
  };
  return new Effect.Parallel(
   [ new Effect.Scale(element, 200, 
      { sync: true, scaleFromCenter: true, scaleContent: true, restoreAfterFinish: true }), 
     new Effect.Opacity(element, { sync: true, to: 0.0 } ) ], 
     Object.extend({ duration: 1.0, 
      beforeSetupInternal: function(effect) {
        Position.absolutize(effect.effects[0].element)
      },
      afterFinishInternal: function(effect) {
         effect.effects[0].element.hide().setStyle(oldStyle); }
     }, arguments[1] || {})
   );
}

Effect.BlindUp = function(element) {
  element = $(element);
  element.makeClipping();
  return new Effect.Scale(element, 0,
    Object.extend({ scaleContent: false, 
      scaleX: false, 
      restoreAfterFinish: true,
      afterFinishInternal: function(effect) {
        effect.element.hide().undoClipping();
      } 
    }, arguments[1] || {})
  );
}

Effect.BlindDown = function(element) {
  element = $(element);
  var elementDimensions = element.getDimensions();
  return new Effect.Scale(element, 100, Object.extend({ 
    scaleContent: false, 
    scaleX: false,
    scaleFrom: 0,
    scaleMode: {originalHeight: elementDimensions.height, originalWidth: elementDimensions.width},
    restoreAfterFinish: true,
    afterSetup: function(effect) {
      effect.element.makeClipping().setStyle({height: '0px'}).show(); 
    },  
    afterFinishInternal: function(effect) {
      effect.element.undoClipping();
    }
  }, arguments[1] || {}));
}

Effect.SwitchOff = function(element) {
  element = $(element);
  var oldOpacity = element.getInlineOpacity();
  return new Effect.Appear(element, Object.extend({
    duration: 0.4,
    from: 0,
    transition: Effect.Transitions.flicker,
    afterFinishInternal: function(effect) {
      new Effect.Scale(effect.element, 1, { 
        duration: 0.3, scaleFromCenter: true,
        scaleX: false, scaleContent: false, restoreAfterFinish: true,
        beforeSetup: function(effect) { 
          effect.element.makePositioned().makeClipping();
        },
        afterFinishInternal: function(effect) {
          effect.element.hide().undoClipping().undoPositioned().setStyle({opacity: oldOpacity});
        }
      })
    }
  }, arguments[1] || {}));
}

Effect.DropOut = function(element) {
  element = $(element);
  var oldStyle = {
    top: element.getStyle('top'),
    left: element.getStyle('left'),
    opacity: element.getInlineOpacity() };
  return new Effect.Parallel(
    [ new Effect.Move(element, {x: 0, y: 100, sync: true }), 
      new Effect.Opacity(element, { sync: true, to: 0.0 }) ],
    Object.extend(
      { duration: 0.5,
        beforeSetup: function(effect) {
          effect.effects[0].element.makePositioned(); 
        },
        afterFinishInternal: function(effect) {
          effect.effects[0].element.hide().undoPositioned().setStyle(oldStyle);
        } 
      }, arguments[1] || {}));
}

Effect.Shake = function(element) {
  element = $(element);
  var oldStyle = {
    top: element.getStyle('top'),
    left: element.getStyle('left') };
    return new Effect.Move(element, 
      { x:  20, y: 0, duration: 0.05, afterFinishInternal: function(effect) {
    new Effect.Move(effect.element,
      { x: -40, y: 0, duration: 0.1,  afterFinishInternal: function(effect) {
    new Effect.Move(effect.element,
      { x:  40, y: 0, duration: 0.1,  afterFinishInternal: function(effect) {
    new Effect.Move(effect.element,
      { x: -40, y: 0, duration: 0.1,  afterFinishInternal: function(effect) {
    new Effect.Move(effect.element,
      { x:  40, y: 0, duration: 0.1,  afterFinishInternal: function(effect) {
    new Effect.Move(effect.element,
      { x: -20, y: 0, duration: 0.05, afterFinishInternal: function(effect) {
        effect.element.undoPositioned().setStyle(oldStyle);
  }}) }}) }}) }}) }}) }});
}

Effect.SlideDown = function(element) {
  element = $(element).cleanWhitespace();
  // SlideDown need to have the content of the element wrapped in a container element with fixed height!
  var oldInnerBottom = element.down().getStyle('bottom');
  var elementDimensions = element.getDimensions();
  return new Effect.Scale(element, 100, Object.extend({ 
    scaleContent: false, 
    scaleX: false, 
    scaleFrom: window.opera ? 0 : 1,
    scaleMode: {originalHeight: elementDimensions.height, originalWidth: elementDimensions.width},
    restoreAfterFinish: true,
    afterSetup: function(effect) {
      effect.element.makePositioned();
      effect.element.down().makePositioned();
      if(window.opera) effect.element.setStyle({top: ''});
      effect.element.makeClipping().setStyle({height: '0px'}).show(); 
    },
    afterUpdateInternal: function(effect) {
      effect.element.down().setStyle({bottom:
        (effect.dims[0] - effect.element.clientHeight) + 'px' }); 
    },
    afterFinishInternal: function(effect) {
      effect.element.undoClipping().undoPositioned();
      effect.element.down().undoPositioned().setStyle({bottom: oldInnerBottom}); }
    }, arguments[1] || {})
  );
}

Effect.SlideUp = function(element) {
  element = $(element).cleanWhitespace();
  var oldInnerBottom = element.down().getStyle('bottom');
  return new Effect.Scale(element, window.opera ? 0 : 1,
   Object.extend({ scaleContent: false, 
    scaleX: false, 
    scaleMode: 'box',
    scaleFrom: 100,
    restoreAfterFinish: true,
    beforeStartInternal: function(effect) {
      effect.element.makePositioned();
      effect.element.down().makePositioned();
      if(window.opera) effect.element.setStyle({top: ''});
      effect.element.makeClipping().show();
    },  
    afterUpdateInternal: function(effect) {
      effect.element.down().setStyle({bottom:
        (effect.dims[0] - effect.element.clientHeight) + 'px' });
    },
    afterFinishInternal: function(effect) {
      effect.element.hide().undoClipping().undoPositioned().setStyle({bottom: oldInnerBottom});
      effect.element.down().undoPositioned();
    }
   }, arguments[1] || {})
  );
}

// Bug in opera makes the TD containing this element expand for a instance after finish 
Effect.Squish = function(element) {
  return new Effect.Scale(element, window.opera ? 1 : 0, { 
    restoreAfterFinish: true,
    beforeSetup: function(effect) {
      effect.element.makeClipping(); 
    },  
    afterFinishInternal: function(effect) {
      effect.element.hide().undoClipping(); 
    }
  });
}

Effect.Grow = function(element) {
  element = $(element);
  var options = Object.extend({
    direction: 'center',
    moveTransition: Effect.Transitions.sinoidal,
    scaleTransition: Effect.Transitions.sinoidal,
    opacityTransition: Effect.Transitions.full
  }, arguments[1] || {});
  var oldStyle = {
    top: element.style.top,
    left: element.style.left,
    height: element.style.height,
    width: element.style.width,
    opacity: element.getInlineOpacity() };

  var dims = element.getDimensions();    
  var initialMoveX, initialMoveY;
  var moveX, moveY;
  
  switch (options.direction) {
    case 'top-left':
      initialMoveX = initialMoveY = moveX = moveY = 0; 
      break;
    case 'top-right':
      initialMoveX = dims.width;
      initialMoveY = moveY = 0;
      moveX = -dims.width;
      break;
    case 'bottom-left':
      initialMoveX = moveX = 0;
      initialMoveY = dims.height;
      moveY = -dims.height;
      break;
    case 'bottom-right':
      initialMoveX = dims.width;
      initialMoveY = dims.height;
      moveX = -dims.width;
      moveY = -dims.height;
      break;
    case 'center':
      initialMoveX = dims.width / 2;
      initialMoveY = dims.height / 2;
      moveX = -dims.width / 2;
      moveY = -dims.height / 2;
      break;
  }
  
  return new Effect.Move(element, {
    x: initialMoveX,
    y: initialMoveY,
    duration: 0.01, 
    beforeSetup: function(effect) {
      effect.element.hide().makeClipping().makePositioned();
    },
    afterFinishInternal: function(effect) {
      new Effect.Parallel(
        [ new Effect.Opacity(effect.element, { sync: true, to: 1.0, from: 0.0, transition: options.opacityTransition }),
          new Effect.Move(effect.element, { x: moveX, y: moveY, sync: true, transition: options.moveTransition }),
          new Effect.Scale(effect.element, 100, {
            scaleMode: { originalHeight: dims.height, originalWidth: dims.width }, 
            sync: true, scaleFrom: window.opera ? 1 : 0, transition: options.scaleTransition, restoreAfterFinish: true})
        ], Object.extend({
             beforeSetup: function(effect) {
               effect.effects[0].element.setStyle({height: '0px'}).show(); 
             },
             afterFinishInternal: function(effect) {
               effect.effects[0].element.undoClipping().undoPositioned().setStyle(oldStyle); 
             }
           }, options)
      )
    }
  });
}

Effect.Shrink = function(element) {
  element = $(element);
  var options = Object.extend({
    direction: 'center',
    moveTransition: Effect.Transitions.sinoidal,
    scaleTransition: Effect.Transitions.sinoidal,
    opacityTransition: Effect.Transitions.none
  }, arguments[1] || {});
  var oldStyle = {
    top: element.style.top,
    left: element.style.left,
    height: element.style.height,
    width: element.style.width,
    opacity: element.getInlineOpacity() };

  var dims = element.getDimensions();
  var moveX, moveY;
  
  switch (options.direction) {
    case 'top-left':
      moveX = moveY = 0;
      break;
    case 'top-right':
      moveX = dims.width;
      moveY = 0;
      break;
    case 'bottom-left':
      moveX = 0;
      moveY = dims.height;
      break;
    case 'bottom-right':
      moveX = dims.width;
      moveY = dims.height;
      break;
    case 'center':  
      moveX = dims.width / 2;
      moveY = dims.height / 2;
      break;
  }
  
  return new Effect.Parallel(
    [ new Effect.Opacity(element, { sync: true, to: 0.0, from: 1.0, transition: options.opacityTransition }),
      new Effect.Scale(element, window.opera ? 1 : 0, { sync: true, transition: options.scaleTransition, restoreAfterFinish: true}),
      new Effect.Move(element, { x: moveX, y: moveY, sync: true, transition: options.moveTransition })
    ], Object.extend({            
         beforeStartInternal: function(effect) {
           effect.effects[0].element.makePositioned().makeClipping(); 
         },
         afterFinishInternal: function(effect) {
           effect.effects[0].element.hide().undoClipping().undoPositioned().setStyle(oldStyle); }
       }, options)
  );
}

Effect.Pulsate = function(element) {
  element = $(element);
  var options    = arguments[1] || {};
  var oldOpacity = element.getInlineOpacity();
  var transition = options.transition || Effect.Transitions.sinoidal;
  var reverser   = function(pos){ return transition(1-Effect.Transitions.pulse(pos, options.pulses)) };
  reverser.bind(transition);
  return new Effect.Opacity(element, 
    Object.extend(Object.extend({  duration: 2.0, from: 0,
      afterFinishInternal: function(effect) { effect.element.setStyle({opacity: oldOpacity}); }
    }, options), {transition: reverser}));
}

Effect.Fold = function(element) {
  element = $(element);
  var oldStyle = {
    top: element.style.top,
    left: element.style.left,
    width: element.style.width,
    height: element.style.height };
  element.makeClipping();
  return new Effect.Scale(element, 5, Object.extend({   
    scaleContent: false,
    scaleX: false,
    afterFinishInternal: function(effect) {
    new Effect.Scale(element, 1, { 
      scaleContent: false, 
      scaleY: false,
      afterFinishInternal: function(effect) {
        effect.element.hide().undoClipping().setStyle(oldStyle);
      } });
  }}, arguments[1] || {}));
};

Effect.Morph = Class.create();
Object.extend(Object.extend(Effect.Morph.prototype, Effect.Base.prototype), {
  initialize: function(element) {
    this.element = $(element);
    if(!this.element) throw(Effect._elementDoesNotExistError);
    var options = Object.extend({
      style: {}
    }, arguments[1] || {});
    if (typeof options.style == 'string') {
      if(options.style.indexOf(':') == -1) {
        var cssText = '', selector = '.' + options.style;
        $A(document.styleSheets).reverse().each(function(styleSheet) {
          if (styleSheet.cssRules) cssRules = styleSheet.cssRules;
          else if (styleSheet.rules) cssRules = styleSheet.rules;
          $A(cssRules).reverse().each(function(rule) {
            if (selector == rule.selectorText) {
              cssText = rule.style.cssText;
              throw $break;
            }
          });
          if (cssText) throw $break;
        });
        this.style = cssText.parseStyle();
        options.afterFinishInternal = function(effect){
          effect.element.addClassName(effect.options.style);
          effect.transforms.each(function(transform) {
            if(transform.style != 'opacity')
              effect.element.style[transform.style] = '';
          });
        }
      } else this.style = options.style.parseStyle();
    } else this.style = $H(options.style)
    this.start(options);
  },
  setup: function(){
    function parseColor(color){
      if(!color || ['rgba(0, 0, 0, 0)','transparent'].include(color)) color = '#ffffff';
      color = color.parseColor();
      return $R(0,2).map(function(i){
        return parseInt( color.slice(i*2+1,i*2+3), 16 ) 
      });
    }
    this.transforms = this.style.map(function(pair){
      var property = pair[0], value = pair[1], unit = null;

      if(value.parseColor('#zzzzzz') != '#zzzzzz') {
        value = value.parseColor();
        unit  = 'color';
      } else if(property == 'opacity') {
        value = parseFloat(value);
        if(Prototype.Browser.IE && (!this.element.currentStyle.hasLayout))
          this.element.setStyle({zoom: 1});
      } else if(Element.CSS_LENGTH.test(value)) {
          var components = value.match(/^([\+\-]?[0-9\.]+)(.*)$/);
          value = parseFloat(components[1]);
          unit = (components.length == 3) ? components[2] : null;
      }

      var originalValue = this.element.getStyle(property);
      return { 
        style: property.camelize(), 
        originalValue: unit=='color' ? parseColor(originalValue) : parseFloat(originalValue || 0), 
        targetValue: unit=='color' ? parseColor(value) : value,
        unit: unit
      };
    }.bind(this)).reject(function(transform){
      return (
        (transform.originalValue == transform.targetValue) ||
        (
          transform.unit != 'color' &&
          (isNaN(transform.originalValue) || isNaN(transform.targetValue))
        )
      )
    });
  },
  update: function(position) {
    var style = {}, transform, i = this.transforms.length;
    while(i--)
      style[(transform = this.transforms[i]).style] = 
        transform.unit=='color' ? '#'+
          (Math.round(transform.originalValue[0]+
            (transform.targetValue[0]-transform.originalValue[0])*position)).toColorPart() +
          (Math.round(transform.originalValue[1]+
            (transform.targetValue[1]-transform.originalValue[1])*position)).toColorPart() +
          (Math.round(transform.originalValue[2]+
            (transform.targetValue[2]-transform.originalValue[2])*position)).toColorPart() :
        transform.originalValue + Math.round(
          ((transform.targetValue - transform.originalValue) * position) * 1000)/1000 + transform.unit;
    this.element.setStyle(style, true);
  }
});

Effect.Transform = Class.create();
Object.extend(Effect.Transform.prototype, {
  initialize: function(tracks){
    this.tracks  = [];
    this.options = arguments[1] || {};
    this.addTracks(tracks);
  },
  addTracks: function(tracks){
    tracks.each(function(track){
      var data = $H(track).values().first();
      this.tracks.push($H({
        ids:     $H(track).keys().first(),
        effect:  Effect.Morph,
        options: { style: data }
      }));
    }.bind(this));
    return this;
  },
  play: function(){
    return new Effect.Parallel(
      this.tracks.map(function(track){
        var elements = [$(track.ids) || $$(track.ids)].flatten();
        return elements.map(function(e){ return new track.effect(e, Object.extend({ sync:true }, track.options)) });
      }).flatten(),
      this.options
    );
  }
});

Element.CSS_PROPERTIES = $w(
  'backgroundColor backgroundPosition borderBottomColor borderBottomStyle ' + 
  'borderBottomWidth borderLeftColor borderLeftStyle borderLeftWidth ' +
  'borderRightColor borderRightStyle borderRightWidth borderSpacing ' +
  'borderTopColor borderTopStyle borderTopWidth bottom clip color ' +
  'fontSize fontWeight height left letterSpacing lineHeight ' +
  'marginBottom marginLeft marginRight marginTop markerOffset maxHeight '+
  'maxWidth minHeight minWidth opacity outlineColor outlineOffset ' +
  'outlineWidth paddingBottom paddingLeft paddingRight paddingTop ' +
  'right textIndent top width wordSpacing zIndex');
  
Element.CSS_LENGTH = /^(([\+\-]?[0-9\.]+)(em|ex|px|in|cm|mm|pt|pc|\%))|0$/;

String.prototype.parseStyle = function(){
  var element = document.createElement('div');
  element.innerHTML = '<div style="' + this + '"></div>';
  var style = element.childNodes[0].style, styleRules = $H();
  
  Element.CSS_PROPERTIES.each(function(property){
    if(style[property]) styleRules[property] = style[property]; 
  });
  if(Prototype.Browser.IE && this.indexOf('opacity') > -1) {
    styleRules.opacity = this.match(/opacity:\s*((?:0|1)?(?:\.\d*)?)/)[1];
  }
  return styleRules;
};

Element.morph = function(element, style) {
  new Effect.Morph(element, Object.extend({ style: style }, arguments[2] || {}));
  return element;
};

['getInlineOpacity','forceRerendering','setContentZoom',
 'collectTextNodes','collectTextNodesIgnoreClass','morph'].each( 
  function(f) { Element.Methods[f] = Element[f]; }
);

Element.Methods.visualEffect = function(element, effect, options) {
  s = effect.dasherize().camelize();
  effect_class = s.charAt(0).toUpperCase() + s.substring(1);
  new Effect[effect_class](element, options);
  return $(element);
};

Element.addMethods();// script.aculo.us controls.js v1.7.1_beta3, Fri May 25 17:19:41 +0200 2007

// Copyright (c) 2005-2007 Thomas Fuchs (http://script.aculo.us, http://mir.aculo.us)
//           (c) 2005-2007 Ivan Krstic (http://blogs.law.harvard.edu/ivan)
//           (c) 2005-2007 Jon Tirsen (http://www.tirsen.com)
// Contributors:
//  Richard Livsey
//  Rahul Bhargava
//  Rob Wills
// 
// script.aculo.us is freely distributable under the terms of an MIT-style license.
// For details, see the script.aculo.us web site: http://script.aculo.us/

// Autocompleter.Base handles all the autocompletion functionality 
// that's independent of the data source for autocompletion. This
// includes drawing the autocompletion menu, observing keyboard
// and mouse events, and similar.
//
// Specific autocompleters need to provide, at the very least, 
// a getUpdatedChoices function that will be invoked every time
// the text inside the monitored textbox changes. This method 
// should get the text for which to provide autocompletion by
// invoking this.getToken(), NOT by directly accessing
// this.element.value. This is to allow incremental tokenized
// autocompletion. Specific auto-completion logic (AJAX, etc)
// belongs in getUpdatedChoices.
//
// Tokenized incremental autocompletion is enabled automatically
// when an autocompleter is instantiated with the 'tokens' option
// in the options parameter, e.g.:
// new Ajax.Autocompleter('id','upd', '/url/', { tokens: ',' });
// will incrementally autocomplete with a comma as the token.
// Additionally, ',' in the above example can be replaced with
// a token array, e.g. { tokens: [',', '\n'] } which
// enables autocompletion on multiple tokens. This is most 
// useful when one of the tokens is \n (a newline), as it 
// allows smart autocompletion after linebreaks.

if(typeof Effect == 'undefined')
  throw("controls.js requires including script.aculo.us' effects.js library");

var Autocompleter = {}
Autocompleter.Base = function() {};
Autocompleter.Base.prototype = {
  baseInitialize: function(element, update, options) {
    element          = $(element)
    this.element     = element; 
    this.update      = $(update);  
    this.hasFocus    = false; 
    this.changed     = false; 
    this.active      = false; 
    this.index       = 0;     
    this.entryCount  = 0;

    if(this.setOptions)
      this.setOptions(options);
    else
      this.options = options || {};

    this.options.paramName    = this.options.paramName || this.element.name;
    this.options.tokens       = this.options.tokens || [];
    this.options.frequency    = this.options.frequency || 0.4;
    this.options.minChars     = this.options.minChars || 1;
    this.options.onShow       = this.options.onShow || 
      function(element, update){ 
        if(!update.style.position || update.style.position=='absolute') {
          update.style.position = 'absolute';
          Position.clone(element, update, {
            setHeight: false, 
            offsetTop: element.offsetHeight
          });
        }
        Effect.Appear(update,{duration:0.15});
      };
    this.options.onHide = this.options.onHide || 
      function(element, update){ new Effect.Fade(update,{duration:0.15}) };

    if(typeof(this.options.tokens) == 'string') 
      this.options.tokens = new Array(this.options.tokens);

    this.observer = null;
    
    this.element.setAttribute('autocomplete','off');

    Element.hide(this.update);

    Event.observe(this.element, 'blur', this.onBlur.bindAsEventListener(this));
    Event.observe(this.element, 'keypress', this.onKeyPress.bindAsEventListener(this));

    // Turn autocomplete back on when the user leaves the page, so that the
    // field's value will be remembered on Mozilla-based browsers.
    Event.observe(window, 'beforeunload', function(){ 
      element.setAttribute('autocomplete', 'on'); 
    });
  },

  show: function() {
    if(Element.getStyle(this.update, 'display')=='none') this.options.onShow(this.element, this.update);
    if(!this.iefix && 
      (Prototype.Browser.IE) &&
      (Element.getStyle(this.update, 'position')=='absolute')) {
      new Insertion.After(this.update, 
       '<iframe id="' + this.update.id + '_iefix" '+
       'style="display:none;position:absolute;filter:progid:DXImageTransform.Microsoft.Alpha(opacity=0);" ' +
       'src="javascript:false;" frameborder="0" scrolling="no"></iframe>');
      this.iefix = $(this.update.id+'_iefix');
    }
    if(this.iefix) setTimeout(this.fixIEOverlapping.bind(this), 50);
  },
  
  fixIEOverlapping: function() {
    Position.clone(this.update, this.iefix, {setTop:(!this.update.style.height)});
    this.iefix.style.zIndex = 1;
    this.update.style.zIndex = 2;
    Element.show(this.iefix);
  },

  hide: function() {
    this.stopIndicator();
    if(Element.getStyle(this.update, 'display')!='none') this.options.onHide(this.element, this.update);
    if(this.iefix) Element.hide(this.iefix);
  },

  startIndicator: function() {
    if(this.options.indicator) Element.show(this.options.indicator);
  },

  stopIndicator: function() {
    if(this.options.indicator) Element.hide(this.options.indicator);
  },

  onKeyPress: function(event) {
    if(this.active)
      switch(event.keyCode) {
       case Event.KEY_TAB:
       case Event.KEY_RETURN:
         this.selectEntry();
         Event.stop(event);
       case Event.KEY_ESC:
         this.hide();
         this.active = false;
         Event.stop(event);
         return;
       case Event.KEY_LEFT:
       case Event.KEY_RIGHT:
         return;
       case Event.KEY_UP:
         this.markPrevious();
         this.render();
         if(Prototype.Browser.WebKit) Event.stop(event);
         return;
       case Event.KEY_DOWN:
         this.markNext();
         this.render();
         if(Prototype.Browser.WebKit) Event.stop(event);
         return;
      }
     else 
       if(event.keyCode==Event.KEY_TAB || event.keyCode==Event.KEY_RETURN || 
         (Prototype.Browser.WebKit > 0 && event.keyCode == 0)) return;

    this.changed = true;
    this.hasFocus = true;

    if(this.observer) clearTimeout(this.observer);
      this.observer = 
        setTimeout(this.onObserverEvent.bind(this), this.options.frequency*1000);
  },

  activate: function() {
    this.changed = false;
    this.hasFocus = true;
    this.getUpdatedChoices();
  },

  onHover: function(event) {
    var element = Event.findElement(event, 'LI');
    if(this.index != element.autocompleteIndex) 
    {
        this.index = element.autocompleteIndex;
        this.render();
    }
    Event.stop(event);
  },
  
  onClick: function(event) {
    var element = Event.findElement(event, 'LI');
    this.index = element.autocompleteIndex;
    this.selectEntry();
    this.hide();
  },
  
  onBlur: function(event) {
    // needed to make click events working
    setTimeout(this.hide.bind(this), 250);
    this.hasFocus = false;
    this.active = false;     
  }, 
  
  render: function() {
    if(this.entryCount > 0) {
      for (var i = 0; i < this.entryCount; i++)
        this.index==i ? 
          Element.addClassName(this.getEntry(i),"selected") : 
          Element.removeClassName(this.getEntry(i),"selected");
      if(this.hasFocus) { 
        this.show();
        this.active = true;
      }
    } else {
      this.active = false;
      this.hide();
    }
  },
  
  markPrevious: function() {
    if(this.index > 0) this.index--
      else this.index = this.entryCount-1;
    this.getEntry(this.index).scrollIntoView(false); //local patch (db2)
  },
  
  markNext: function() {
    if(this.index < this.entryCount-1) this.index++
      else this.index = 0;
    this.getEntry(this.index).scrollIntoView(false);
  },
  
  getEntry: function(index) {
    return this.update.firstChild.childNodes[index];
  },
  
  getCurrentEntry: function() {
    return this.getEntry(this.index);
  },
  
  selectEntry: function() {
    this.active = false;
    this.updateElement(this.getCurrentEntry());
  },

  updateElement: function(selectedElement) {
    if (this.options.updateElement) {
      this.options.updateElement(selectedElement);
      return;
    }
    var value = '';
    if (this.options.select) {
      var nodes = document.getElementsByClassName(this.options.select, selectedElement) || [];
      if(nodes.length>0) value = Element.collectTextNodes(nodes[0], this.options.select);
    } else
      value = Element.collectTextNodesIgnoreClass(selectedElement, 'informal');
    
    var lastTokenPos = this.findLastToken();
    if (lastTokenPos != -1) {
      var newValue = this.element.value.substr(0, lastTokenPos + 1);
      var whitespace = this.element.value.substr(lastTokenPos + 1).match(/^\s+/);
      if (whitespace)
        newValue += whitespace[0];
      this.element.value = newValue + value;
    } else {
      this.element.value = value;
    }
    this.element.focus();
    
    if (this.options.afterUpdateElement)
      this.options.afterUpdateElement(this.element, selectedElement);
  },

  updateChoices: function(choices) {
    if(!this.changed && this.hasFocus) {
      this.update.innerHTML = choices;
      Element.cleanWhitespace(this.update);
      Element.cleanWhitespace(this.update.down());

      if(this.update.firstChild && this.update.down().childNodes) {
        this.entryCount = 
          this.update.down().childNodes.length;
        for (var i = 0; i < this.entryCount; i++) {
          var entry = this.getEntry(i);
          entry.autocompleteIndex = i;
          this.addObservers(entry);
        }
      } else { 
        this.entryCount = 0;
      }

      this.stopIndicator();
      this.index = 0;
      
      if(this.entryCount==1 && this.options.autoSelect) {
        this.selectEntry();
        this.hide();
      } else {
        this.render();
      }
    }
  },

  addObservers: function(element) {
    Event.observe(element, "mouseover", this.onHover.bindAsEventListener(this));
    Event.observe(element, "click", this.onClick.bindAsEventListener(this));
  },

  onObserverEvent: function() {
    this.changed = false;   
    if(this.getToken().length>=this.options.minChars) {
      this.getUpdatedChoices();
    } else {
      this.active = false;
      this.hide();
    }
  },

  getToken: function() {
    var tokenPos = this.findLastToken();
    if (tokenPos != -1)
      var ret = this.element.value.substr(tokenPos + 1).replace(/^\s+/,'').replace(/\s+$/,'');
    else
      var ret = this.element.value;

    return /\n/.test(ret) ? '' : ret;
  },

  findLastToken: function() {
    var lastTokenPos = -1;

    for (var i=0; i<this.options.tokens.length; i++) {
      var thisTokenPos = this.element.value.lastIndexOf(this.options.tokens[i]);
      if (thisTokenPos > lastTokenPos)
        lastTokenPos = thisTokenPos;
    }
    return lastTokenPos;
  }
}

Ajax.Autocompleter = Class.create();
Object.extend(Object.extend(Ajax.Autocompleter.prototype, Autocompleter.Base.prototype), {
  initialize: function(element, update, url, options) {
    this.baseInitialize(element, update, options);
    this.options.asynchronous  = true;
    this.options.onComplete    = this.onComplete.bind(this);
    this.options.defaultParams = this.options.parameters || null;
    this.url                   = url;
  },

  getUpdatedChoices: function() {
    this.startIndicator();
    
    var entry = encodeURIComponent(this.options.paramName) + '=' + 
      encodeURIComponent(this.getToken());

    this.options.parameters = this.options.callback ?
      this.options.callback(this.element, entry) : entry;

    if(this.options.defaultParams) 
      this.options.parameters += '&' + this.options.defaultParams;
    
    new Ajax.Request(this.url, this.options);
  },

  onComplete: function(request) {
    this.updateChoices(request.responseText);
  }

});

// The local array autocompleter. Used when you'd prefer to
// inject an array of autocompletion options into the page, rather
// than sending out Ajax queries, which can be quite slow sometimes.
//
// The constructor takes four parameters. The first two are, as usual,
// the id of the monitored textbox, and id of the autocompletion menu.
// The third is the array you want to autocomplete from, and the fourth
// is the options block.
//
// Extra local autocompletion options:
// - choices - How many autocompletion choices to offer
//
// - partialSearch - If false, the autocompleter will match entered
//                    text only at the beginning of strings in the 
//                    autocomplete array. Defaults to true, which will
//                    match text at the beginning of any *word* in the
//                    strings in the autocomplete array. If you want to
//                    search anywhere in the string, additionally set
//                    the option fullSearch to true (default: off).
//
// - fullSsearch - Search anywhere in autocomplete array strings.
//
// - partialChars - How many characters to enter before triggering
//                   a partial match (unlike minChars, which defines
//                   how many characters are required to do any match
//                   at all). Defaults to 2.
//
// - ignoreCase - Whether to ignore case when autocompleting.
//                 Defaults to true.
//
// It's possible to pass in a custom function as the 'selector' 
// option, if you prefer to write your own autocompletion logic.
// In that case, the other options above will not apply unless
// you support them.

Autocompleter.Local = Class.create();
Autocompleter.Local.prototype = Object.extend(new Autocompleter.Base(), {
  initialize: function(element, update, array, options) {
    this.baseInitialize(element, update, options);
    this.options.array = array;
  },

  getUpdatedChoices: function() {
    this.updateChoices(this.options.selector(this));
  },

  setOptions: function(options) {
    this.options = Object.extend({
      choices: 10,
      partialSearch: true,
      partialChars: 2,
      ignoreCase: true,
      fullSearch: false,
      selector: function(instance) {
        var ret       = []; // Beginning matches
        var partial   = []; // Inside matches
        var entry     = instance.getToken();
        var count     = 0;

        for (var i = 0; i < instance.options.array.length &&  
          ret.length < instance.options.choices ; i++) { 

          var elem = instance.options.array[i];
          var foundPos = instance.options.ignoreCase ? 
            elem.toLowerCase().indexOf(entry.toLowerCase()) : 
            elem.indexOf(entry);

          while (foundPos != -1) {
            if (foundPos == 0 && elem.length != entry.length) { 
              ret.push("<li><strong>" + elem.substr(0, entry.length) + "</strong>" + 
                elem.substr(entry.length) + "</li>");
              break;
            } else if (entry.length >= instance.options.partialChars && 
              instance.options.partialSearch && foundPos != -1) {
              if (instance.options.fullSearch || /\s/.test(elem.substr(foundPos-1,1))) {
                partial.push("<li>" + elem.substr(0, foundPos) + "<strong>" +
                  elem.substr(foundPos, entry.length) + "</strong>" + elem.substr(
                  foundPos + entry.length) + "</li>");
                break;
              }
            }

            foundPos = instance.options.ignoreCase ? 
              elem.toLowerCase().indexOf(entry.toLowerCase(), foundPos + 1) : 
              elem.indexOf(entry, foundPos + 1);

          }
        }
        if (partial.length)
          ret = ret.concat(partial.slice(0, instance.options.choices - ret.length))
        return "<ul>" + ret.join('') + "</ul>";
      }
    }, options || {});
  }
});

// AJAX in-place editor
//
// see documentation on http://wiki.script.aculo.us/scriptaculous/show/Ajax.InPlaceEditor

// Use this if you notice weird scrolling problems on some browsers,
// the DOM might be a bit confused when this gets called so do this
// waits 1 ms (with setTimeout) until it does the activation
Field.scrollFreeActivate = function(field) {
  setTimeout(function() {
    Field.activate(field);
  }, 1);
}

Ajax.InPlaceEditor = Class.create();
Ajax.InPlaceEditor.defaultHighlightColor = "#FFFF99";
Ajax.InPlaceEditor.prototype = {
  initialize: function(element, url, options) {
    this.url = url;
    this.element = $(element);

    this.options = Object.extend({
      paramName: "value",
      okButton: true,
      okLink: false,
      okText: "ok",
      cancelButton: false,
      cancelLink: true,
      cancelText: "cancel",
      textBeforeControls: '',
      textBetweenControls: '',
      textAfterControls: '',
      savingText: "Saving...",
      clickToEditText: "Click to edit",
      okText: "ok",
      rows: 1,
      onComplete: function(transport, element) {
        new Effect.Highlight(element, {startcolor: this.options.highlightcolor});
      },
      onFailure: function(transport) {
        alert("Error communicating with the server: " + transport.responseText.stripTags());
      },
      callback: function(form) {
        return Form.serialize(form);
      },
      handleLineBreaks: true,
      loadingText: 'Loading...',
      savingClassName: 'inplaceeditor-saving',
      loadingClassName: 'inplaceeditor-loading',
      formClassName: 'inplaceeditor-form',
      highlightcolor: Ajax.InPlaceEditor.defaultHighlightColor,
      highlightendcolor: "#FFFFFF",
      externalControl: null,
      submitOnBlur: false,
      ajaxOptions: {},
      evalScripts: false
    }, options || {});

    if(!this.options.formId && this.element.id) {
      this.options.formId = this.element.id + "-inplaceeditor";
      if ($(this.options.formId)) {
        // there's already a form with that name, don't specify an id
        this.options.formId = null;
      }
    }
    
    if (this.options.externalControl) {
      this.options.externalControl = $(this.options.externalControl);
    }
    
    this.originalBackground = Element.getStyle(this.element, 'background-color');
    if (!this.originalBackground) {
      this.originalBackground = "transparent";
    }
    
    this.element.title = this.options.clickToEditText;
    
    this.onclickListener = this.enterEditMode.bindAsEventListener(this);
    this.mouseoverListener = this.enterHover.bindAsEventListener(this);
    this.mouseoutListener = this.leaveHover.bindAsEventListener(this);
    Event.observe(this.element, 'click', this.onclickListener);
    Event.observe(this.element, 'mouseover', this.mouseoverListener);
    Event.observe(this.element, 'mouseout', this.mouseoutListener);
    if (this.options.externalControl) {
      Event.observe(this.options.externalControl, 'click', this.onclickListener);
      Event.observe(this.options.externalControl, 'mouseover', this.mouseoverListener);
      Event.observe(this.options.externalControl, 'mouseout', this.mouseoutListener);
    }
  },
  enterEditMode: function(evt) {
    if (this.saving) return;
    if (this.editing) return;
    this.editing = true;
    this.onEnterEditMode();
    if (this.options.externalControl) {
      Element.hide(this.options.externalControl);
    }
    Element.hide(this.element);
    this.createForm();
    this.element.parentNode.insertBefore(this.form, this.element);
    if (!this.options.loadTextURL) Field.scrollFreeActivate(this.editField);
    // stop the event to avoid a page refresh in Safari
    if (evt) {
      Event.stop(evt);
    }
    return false;
  },
  createForm: function() {
    this.form = document.createElement("form");
    this.form.id = this.options.formId;
    Element.addClassName(this.form, this.options.formClassName)
    this.form.onsubmit = this.onSubmit.bind(this);

    this.createEditField();

    if (this.options.textarea) {
      var br = document.createElement("br");
      this.form.appendChild(br);
    }
    
    if (this.options.textBeforeControls)
      this.form.appendChild(document.createTextNode(this.options.textBeforeControls));

    if (this.options.okButton) {
      var okButton = document.createElement("input");
      okButton.type = "submit";
      okButton.value = this.options.okText;
      okButton.className = 'editor_ok_button';
      this.form.appendChild(okButton);
    }
    
    if (this.options.okLink) {
      var okLink = document.createElement("a");
      okLink.href = "#";
      okLink.appendChild(document.createTextNode(this.options.okText));
      okLink.onclick = this.onSubmit.bind(this);
      okLink.className = 'editor_ok_link';
      this.form.appendChild(okLink);
    }
    
    if (this.options.textBetweenControls && 
      (this.options.okLink || this.options.okButton) && 
      (this.options.cancelLink || this.options.cancelButton))
      this.form.appendChild(document.createTextNode(this.options.textBetweenControls));
      
    if (this.options.cancelButton) {
      var cancelButton = document.createElement("input");
      cancelButton.type = "submit";
      cancelButton.value = this.options.cancelText;
      cancelButton.onclick = this.onclickCancel.bind(this);
      cancelButton.className = 'editor_cancel_button';
      this.form.appendChild(cancelButton);
    }

    if (this.options.cancelLink) {
      var cancelLink = document.createElement("a");
      cancelLink.href = "#";
      cancelLink.appendChild(document.createTextNode(this.options.cancelText));
      cancelLink.onclick = this.onclickCancel.bind(this);
      cancelLink.className = 'editor_cancel editor_cancel_link';      
      this.form.appendChild(cancelLink);
    }
    
    if (this.options.textAfterControls)
      this.form.appendChild(document.createTextNode(this.options.textAfterControls));
  },
  hasHTMLLineBreaks: function(string) {
    if (!this.options.handleLineBreaks) return false;
    return string.match(/<br/i) || string.match(/<p>/i);
  },
  convertHTMLLineBreaks: function(string) {
    return string.replace(/<br>/gi, "\n").replace(/<br\/>/gi, "\n").replace(/<\/p>/gi, "\n").replace(/<p>/gi, "");
  },
  createEditField: function() {
    var text;
    if(this.options.loadTextURL) {
      text = this.options.loadingText;
    } else {
      text = this.getText();
    }

    var obj = this;
    
    if (this.options.rows == 1 && !this.hasHTMLLineBreaks(text)) {
      this.options.textarea = false;
      var textField = document.createElement("input");
      textField.obj = this;
      textField.type = "text";
      textField.name = this.options.paramName;
      textField.value = text;
      textField.style.backgroundColor = this.options.highlightcolor;
      textField.className = 'editor_field';
      var size = this.options.size || this.options.cols || 0;
      if (size != 0) textField.size = size;
      if (this.options.submitOnBlur)
        textField.onblur = this.onSubmit.bind(this);
      this.editField = textField;
    } else {
      this.options.textarea = true;
      var textArea = document.createElement("textarea");
      textArea.obj = this;
      textArea.name = this.options.paramName;
      textArea.value = this.convertHTMLLineBreaks(text);
      textArea.rows = this.options.rows;
      textArea.cols = this.options.cols || 40;
      textArea.className = 'editor_field';      
      if (this.options.submitOnBlur)
        textArea.onblur = this.onSubmit.bind(this);
      this.editField = textArea;
    }
    
    if(this.options.loadTextURL) {
      this.loadExternalText();
    }
    this.form.appendChild(this.editField);
  },
  getText: function() {
    return this.element.innerHTML;
  },
  loadExternalText: function() {
    Element.addClassName(this.form, this.options.loadingClassName);
    this.editField.disabled = true;
    new Ajax.Request(
      this.options.loadTextURL,
      Object.extend({
        asynchronous: true,
        onComplete: this.onLoadedExternalText.bind(this)
      }, this.options.ajaxOptions)
    );
  },
  onLoadedExternalText: function(transport) {
    Element.removeClassName(this.form, this.options.loadingClassName);
    this.editField.disabled = false;
    this.editField.value = transport.responseText.stripTags();
    Field.scrollFreeActivate(this.editField);
  },
  onclickCancel: function() {
    this.onComplete();
    this.leaveEditMode();
    return false;
  },
  onFailure: function(transport) {
    this.options.onFailure(transport);
    if (this.oldInnerHTML) {
      this.element.innerHTML = this.oldInnerHTML;
      this.oldInnerHTML = null;
    }
    return false;
  },
  onSubmit: function() {
    // onLoading resets these so we need to save them away for the Ajax call
    var form = this.form;
    var value = this.editField.value;
    
    // do this first, sometimes the ajax call returns before we get a chance to switch on Saving...
    // which means this will actually switch on Saving... *after* we've left edit mode causing Saving...
    // to be displayed indefinitely
    this.onLoading();
    
    if (this.options.evalScripts) {
      new Ajax.Request(
        this.url, Object.extend({
          parameters: this.options.callback(form, value),
          onComplete: this.onComplete.bind(this),
          onFailure: this.onFailure.bind(this),
          asynchronous:true, 
          evalScripts:true
        }, this.options.ajaxOptions));
    } else  {
      new Ajax.Updater(
        { success: this.element,
          // don't update on failure (this could be an option)
          failure: null }, 
        this.url, Object.extend({
          parameters: this.options.callback(form, value),
          onComplete: this.onComplete.bind(this),
          onFailure: this.onFailure.bind(this)
        }, this.options.ajaxOptions));
    }
    // stop the event to avoid a page refresh in Safari
    if (arguments.length > 1) {
      Event.stop(arguments[0]);
    }
    return false;
  },
  onLoading: function() {
    this.saving = true;
    this.removeForm();
    this.leaveHover();
    this.showSaving();
  },
  showSaving: function() {
    this.oldInnerHTML = this.element.innerHTML;
    this.element.innerHTML = this.options.savingText;
    Element.addClassName(this.element, this.options.savingClassName);
    this.element.style.backgroundColor = this.originalBackground;
    Element.show(this.element);
  },
  removeForm: function() {
    if(this.form) {
      if (this.form.parentNode) Element.remove(this.form);
      this.form = null;
    }
  },
  enterHover: function() {
    if (this.saving) return;
    this.element.style.backgroundColor = this.options.highlightcolor;
    if (this.effect) {
      this.effect.cancel();
    }
    Element.addClassName(this.element, this.options.hoverClassName)
  },
  leaveHover: function() {
    if (this.options.backgroundColor) {
      this.element.style.backgroundColor = this.oldBackground;
    }
    Element.removeClassName(this.element, this.options.hoverClassName)
    if (this.saving) return;
    this.effect = new Effect.Highlight(this.element, {
      startcolor: this.options.highlightcolor,
      endcolor: this.options.highlightendcolor,
      restorecolor: this.originalBackground
    });
  },
  leaveEditMode: function() {
    Element.removeClassName(this.element, this.options.savingClassName);
    this.removeForm();
    this.leaveHover();
    this.element.style.backgroundColor = this.originalBackground;
    Element.show(this.element);
    if (this.options.externalControl) {
      Element.show(this.options.externalControl);
    }
    this.editing = false;
    this.saving = false;
    this.oldInnerHTML = null;
    this.onLeaveEditMode();
  },
  onComplete: function(transport) {
    this.leaveEditMode();
    this.options.onComplete.bind(this)(transport, this.element);
  },
  onEnterEditMode: function() {},
  onLeaveEditMode: function() {},
  dispose: function() {
    if (this.oldInnerHTML) {
      this.element.innerHTML = this.oldInnerHTML;
    }
    this.leaveEditMode();
    Event.stopObserving(this.element, 'click', this.onclickListener);
    Event.stopObserving(this.element, 'mouseover', this.mouseoverListener);
    Event.stopObserving(this.element, 'mouseout', this.mouseoutListener);
    if (this.options.externalControl) {
      Event.stopObserving(this.options.externalControl, 'click', this.onclickListener);
      Event.stopObserving(this.options.externalControl, 'mouseover', this.mouseoverListener);
      Event.stopObserving(this.options.externalControl, 'mouseout', this.mouseoutListener);
    }
  }
};

Ajax.InPlaceCollectionEditor = Class.create();
Object.extend(Ajax.InPlaceCollectionEditor.prototype, Ajax.InPlaceEditor.prototype);
Object.extend(Ajax.InPlaceCollectionEditor.prototype, {
  createEditField: function() {
    if (!this.cached_selectTag) {
      var selectTag = document.createElement("select");
      var collection = this.options.collection || [];
      var optionTag;
      collection.each(function(e,i) {
        optionTag = document.createElement("option");
        optionTag.value = (e instanceof Array) ? e[0] : e;
        if((typeof this.options.value == 'undefined') && 
          ((e instanceof Array) ? this.element.innerHTML == e[1] : e == optionTag.value)) optionTag.selected = true;
        if(this.options.value==optionTag.value) optionTag.selected = true;
        optionTag.appendChild(document.createTextNode((e instanceof Array) ? e[1] : e));
        selectTag.appendChild(optionTag);
      }.bind(this));
      this.cached_selectTag = selectTag;
    }

    this.editField = this.cached_selectTag;
    if(this.options.loadTextURL) this.loadExternalText();
    this.form.appendChild(this.editField);
    this.options.callback = function(form, value) {
      return "value=" + encodeURIComponent(value);
    }
  }
});

// Delayed observer, like Form.Element.Observer, 
// but waits for delay after last key input
// Ideal for live-search fields

Form.Element.DelayedObserver = Class.create();
Form.Element.DelayedObserver.prototype = {
  initialize: function(element, delay, callback) {
    this.delay     = delay || 0.5;
    this.element   = $(element);
    this.callback  = callback;
    this.timer     = null;
    this.lastValue = $F(this.element); 
    Event.observe(this.element,'keyup',this.delayedListener.bindAsEventListener(this));
  },
  delayedListener: function(event) {
    if(this.lastValue == $F(this.element)) return;
    if(this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(this.onTimerEvent.bind(this), this.delay * 1000);
    this.lastValue = $F(this.element);
  },
  onTimerEvent: function() {
    this.timer = null;
    this.callback(this.element, $F(this.element));
  }
};
