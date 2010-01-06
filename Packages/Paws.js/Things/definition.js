return (function(){ var definition, rootDefinition;
  rootDefinition = [
    paws.string.beget(''),
    paws.bool['void']
  ];
  definition = paws.tuple.beget({ content : rootDefinition });
  
  definition.errors = {
    invalidName: new(Error)("The first element of a definition must be an " +
                            "`infrastructure string`"),
    invalidStructure: new(Error)("A definition must contain either two or " +
                                 "three elements: name, value, and an " +
                                 "optional metadata list")
  };
  
  definition.constructor = function (blueprint) {
    // Hell, definitions are really just tuples that are a bit stricter about
    // their content
    if ( typeof blueprint         !== 'undefined' &&
         typeof blueprint.content !== 'undefined' ) {
      if (!paws.string.isPrototypeOf(blueprint.content[0]) &&
          !paws.string === blueprint.content[0]) {
        throw(definition.errors.invalidName) };
      if (blueprint.content.length > 3 || blueprint.content.length < 2) {
        throw(definition.errors.invalidStructure) };
      
      if (blueprint.content.length < 3) {
        blueprint.content.push(paws.list.beget()) };
    };
    
    paws.tuple.constructor.apply(this, arguments);
  };
  
  // This should look like, either: `'foo':(…)` or `'foo':(…):(…)`.
  definition._lens = function (eyes, styles) {
    return eyes.stylize(this._store().map(function (item) {
      return eyes.stringify(item, styles) }).join(':'),
      styles.tuple, styles) };
  
  // FIXME: Is running `paws.tuple.constructor` twice dangerous? Because we
  //        already ran it above, when `beget()`ing `paws.definition` from
  //        `paws.tuple`.
  definition.constructor({ content : rootDefinition });
  
  return definition;
})()
