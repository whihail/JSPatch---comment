var global = this

;(function() {

  var callbacks = {}
  var callbackID = 0
  
  
//  /**
//   * 将OC方法名转化成js的方法名  在此处并没有起到作用，可能作者 bang 忘记去掉啦！已经删除并 pull request，bang也merag啦
//   **/
//  var _methodNameOCToJS = function(name) {
//    name = name.replace(/\:/g, '_')   //利用正则将所有“：”字符替换成“_”
//    if (name[name.length - 1] == '_') {
//      return name.substr(0, name.length - 1)   //将方法名的最后'_'字符去除
//    }
//    return name
//  }

  /**
   * 将 OC 对象遍历 format 为js对象
   **/
  var _formatOCToJS = function(obj) {
    if (obj === undefined || obj === null) return false
    if (typeof obj == "object") {     //如果是js对象
      if (obj.__obj) return obj        //如果这个对象由OC对象转化而来
      if (obj.__isNil) return false    //如果这个对象为空
    }
    if (obj instanceof Array) {       //如果这个对象为Array的衍生对象
      var ret = []
      obj.forEach(function(o) {       //遍历这个Array，将每一个OC成员对象转化为js对象,放入新Array
        ret.push(_formatOCToJS(o))
      })
      return ret
    }
    if (obj instanceof Function) {      //如果这个obj对象是Function，format 成以下function
        return function() {
            var args = Array.prototype.slice.call(arguments)     //将参数arguments转化为Array对象
            var formatedArgs = _OC_formatJSToOC(args)            //通过调用OC方法，将参数args数组转化为OC对象
            for (var i = 0; i < args.length; i++) {
                if (args[i] === null || args[i] === undefined || args[i] === false) {
                formatedArgs.splice(i, 1, undefined)
                } else if (args[i] == nsnull) {
                formatedArgs.splice(i, 1, null)
                }
            }
            return _OC_formatOCToJS(obj.apply(obj, formatedArgs))        //执行obj方法，并调用OC中的方法将返回值format成js格式对象
        }
    }
    if (obj instanceof Object) {            //如果obj是Object的衍生对象，则通过递归将obj对象的每个属性对象都转化为js对象
      var ret = {}
      for (var key in obj) {
        ret[key] = _formatOCToJS(obj[key])
      }
      return ret
    }
    return obj
  }
  
  
  /**
   *  执行OC方法，并将返回值转化为js对象
   */
  var _methodFunc = function(instance, clsName, methodName, args, isSuper, isPerformSelector) {
    var selectorName = methodName
    if (!isPerformSelector) {
      methodName = methodName.replace(/__/g, "-")     //将所有的“__”字符替换成“-”
      selectorName = methodName.replace(/_/g, ":").replace(/-/g, "_")     //将所有的“_”字符替换成“:”字符，然后将所有的"-"字符替换成“_”字符
      var marchArr = selectorName.match(/:/g)        //搜索所有的“:”字符
      var numOfArgs = marchArr ? marchArr.length : 0
      if (args.length > numOfArgs) {
        selectorName += ":"             //如否参数个数大于方法名中的“:”字符数，则在方法名最后加上字符":"
      }
    }
    var ret = instance ? _OC_callI(instance, selectorName, args, isSuper):
                         _OC_callC(clsName, selectorName, args)          //如果instance值为YES，则为实例对象，否则为类对象
    return _formatOCToJS(ret)            //将调用OC方法的返回值转化为js对象 返回
  }

  
  /**
   * 为Object对象增加“__c”属性，
   * __c默认值为value键所对应的值，既function(methodName){}。
   * configurable:  如果为false，则任何尝试删除目标属性或修改属性以下特性（writable, configurable, enumerable）的行为将被无效化。
   * enumerable:    是否能在for...in循环中遍历出来或在Object.keys中列举出来。
   */
  Object.defineProperty(Object.prototype, "__c", {value: function(methodName) {
    if (this instanceof Boolean) {
      return function() {
        return false
      }
    }
    
    if (!this.__obj && !this.__clsName) {
      return this[methodName].bind(this);
    }

    var self = this
    if (methodName == 'super') {
      return function() {
        return {__obj: self.__obj, __clsName: self.__clsName, __isSuper: 1}     //如果methodName等于“super”，则返回此对象并将对象__issuper属性值设置为1。
      }
    }

    if (methodName.indexOf('performSelector') > -1) {
      if (methodName == 'performSelector') {       //如果nethodName == 'performSelector'，则直接放回一个jsFunction，返回值为_methodFunc()执行结果
        return function(){
          var args = Array.prototype.slice.call(arguments)       //将参数转化为Array
          return _methodFunc(self.__obj, self.__clsName, args[0], args.splice(1), self.__isSuper, true)
        }
      } else if (methodName == 'performSelectorInOC') {   //处理多线程情况，脱离 JavaScriptCore 的锁后才在OC中执行
        return function(){
          var args = Array.prototype.slice.call(arguments)
          return {__isPerformInOC:1, obj:self.__obj, clsName:self.__clsName, sel: args[0], args: args[1], cb: args[2]}
        }
      }
    }
    return function(){             //执行__c()后，返回值为一个jsFunction，此jsFunction返回值为_methodFunc()执行结果
      var args = Array.prototype.slice.call(arguments)
      return _methodFunc(self.__obj, self.__clsName, methodName, args, self.__isSuper)
    }
  }, configurable:false, enumerable: false})

  
  /**
   * _require将一个字段标记为类对象
   */
  var _require = function(clsName) {
    if (!global[clsName]) {
      global[clsName] = {
        __clsName: clsName
      }
    } 
    return global[clsName]
  }

  /**
   * 将多个字段分别标记为类对象
   */
  global.require = function(clsNames) {
    var lastRequire
    clsNames.split(',').forEach(function(clsName) {
      lastRequire = _require(clsName.trim())
    })
    return lastRequire
  }

  
  /**
   * 将js方法用newMethods对象以newMethods[methodName] = [方法参数个数,方法体对象]的结构保存
   */
  var _formatDefineMethods = function(methods, newMethods) {
    for (var methodName in methods) {
      (function(){                                     //此闭包为了保持执行环境中的methodName的值
       var originMethod = methods[methodName]
        newMethods[methodName] = [originMethod.length, function() {     //originMethod.length 表示function的参数个数
          var args = _formatOCToJS(Array.prototype.slice.call(arguments))  //将参数转化为数组并转化为js数组
          var lastSelf = global.self
          var ret;
          try {
            global.self = args[0]
            args.splice(0,1)
            ret = originMethod.apply(originMethod, args)
            global.self = lastSelf
          } catch(e) {
            _OC_catch(e.message, e.stack)   //调用OC的catch处理
          }
          return ret             //将jsFunction执行的返回值返回给OC，如无返回值则ret为undefined
        }]    //将新方法以[function参数个数，function对象]的形式赋值给newMethods
      })()
    }
  }

  
  /**
   * 定义defineClass方法对象，作用是替换类方法和实例方法，
   */
  global.defineClass = function(declaration, instMethods, clsMethods) {
    var newInstMethods = {}, newClsMethods = {}
    _formatDefineMethods(instMethods, newInstMethods)   //通过instMethods内容以 newInstMethods[methodName] = [方法参数个数,方法体对象]的结构保存在到 newClsMethods中
    _formatDefineMethods(clsMethods, newClsMethods)     //通过clsMethods内容以 newClsMethods[methodName] = [方法参数个数,方法体对象]的结构保存在到 newClsMethods中

    var ret = _OC_defineClass(declaration, newInstMethods, newClsMethods)  //调用OC代码对方法实现进行替换等操作

    return require(ret["cls"])   //将OC中返回的类名require标记为类对象
  }

  /**
   * block支持
   */
  global.block = function(args, cb) {
    var slf = this
    if (args instanceof Function) {
      cb = args
      args = ''
    }
    var callback = function() {
      var args = Array.prototype.slice.call(arguments)
      return cb.apply(slf, _formatOCToJS(args))
    }
    return {args: args, cb: callback, __isBlock: 1}
  }
  
  
  /**
   *  封装打印OC日志模块
   */
  if (global.console) {
    var jsLogger = console.log;
    global.console.log = function() {
      global._OC_log.apply(global, arguments);
      if (jsLogger) {
        jsLogger.apply(global.console, arguments);
      }
    }
  } else {
    global.console = {
      log: global._OC_log
    }
  }
  
  /**
   *  初始化YES，NO，nsnull的值
   */
  global.YES = 1
  global.NO = 0
  global.nsnull = _OC_null
  global._formatOCToJS = _formatOCToJS
  
})()