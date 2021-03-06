/**
    Any type that conforms to this protocol
    can be passed as a requirement to Vapor's
    type-safe route calls.
*/
public protocol StringInitializable {
    init?(from string: String) throws
}

///Allow the Int type to be a type-safe routing parameter
extension Int: StringInitializable {
    public init?(from string: String) throws {
        guard let int = Int(string) else {
            return nil
        }

        self = int
    }
}

///Allow the String type to be a type-safe routing parameter
extension String: StringInitializable {
    public init?(from string: String) throws {
        self = string
    }
}

extension Application {
    /**
        Creates a route for all HTTP methods.
        `get`, `post`, `put`, `patch`, and `delete`.
    */
    public final func any(_ path: String, handler: Route.Handler) {
        self.get(path, handler: handler)
        self.post(path, handler: handler)
        self.put(path, handler: handler)
        self.patch(path, handler: handler)
        self.delete(path, handler: handler)
    }

    /**
        Creates standard Create, Read, Update, Delete routes
        using the Handlers from a supplied `ResourceController`.

        Note: You are responsible for pluralizing your endpoints.
    */
    public final func resource<Resource: ResourceController>(
                                _ path: String,
                               makeControllerWith controllerFactory: () -> Resource) {
        //GET /entities
        self.get(path) { request in
            return try controllerFactory().index(request)
        }

        //POST /entities
        self.post(path) { request in
            return try controllerFactory().index(request)
        }

        //GET /entities/:id
        self.get(path, Resource.Item.self) { request, item in
            return try controllerFactory().show(request, item: item)
        }

        //PUT /entities/:id
        self.put(path, Resource.Item.self) { request, item in
            return try controllerFactory().update(request, item: item)
        }

        //DELETE /intities/:id
        self.delete(path, Resource.Item.self) { request, item in
            return try controllerFactory().destroy(request, item: item)
        }

    }

    /**
        Add resource controller for specified path

        - parameter path: path associated w/ resource controller
        - parameter controller: controller type to use
     */
    public final func resource<Resource: ResourceController
                               where Resource: ApplicationInitializable>(
                                    _ path: String,
                                    controller: Resource.Type) {
        resource(path) {
            return controller.init(application: self)
        }
    }

    /**
     Add resource controller for specified path

     - parameter path: path associated w/ resource controller
     - parameter controller: controller type to use
     */
    public final func resource<Resource: ResourceController
                               where Resource: DefaultInitializable>(
                                    _ path: String,
                                    controller: Resource.Type) {
        resource(path) {
            return controller.init()
        }
    }

    /**
        Adds a route handled by a type that can be initialized with an `Application`.
        This method is useful if you have a controller and would like to add an action
        that is not a common REST action.

        Here's an example of how you would add a route with this method:

        ```app.add(.get, path: "/foo", action: TestController.foo)```

        - parameter method: The `Request.Method` that the action should be executed for.
        - parameter path: The HTTP path that the action can run at.
        - parameter action: The curried action to run on the provided type.
     */
    public final func add<ActionController: ApplicationInitializable>(
        _ method: Request.Method,
        path: String,
        action: (ActionController) -> (Request) throws -> ResponseRepresentable) {
        add(method, path: path, action: action) {
            ActionController(application: self)
        }
    }

    /**
         Adds a route handled by a type that can be defaultly initialized.
         This method is useful if you have a controller and would like to add an action
         that is not a common REST action.

         Here's an example of how you would add a route with this method:

         ```app.add(.get, path: "/bar", action: TestController.bar)```

         - parameter method: The `Request.Method` that the action should be executed for.
         - parameter path: The HTTP path that the action can run at.
         - parameter action: The curried action to run on the provided type.
     */
    public final func add<ActionController: DefaultInitializable>(
        _ method: Request.Method,
        path: String,
        action: (ActionController) -> (Request) throws -> ResponseRepresentable) {
        add(method, path: path, action: action) {
            ActionController()
        }
    }

    /**
        Adds a route handled by a type that can be initialized via the provided factory.
        This method is useful if you have a controller and would like to add an action
        that is not a common REST action, and you need to handle initialization yourself.

        Here's an example of how you would add a route with this method:

        ```app.add(.get, path: "/baz", action: TestController.baz) { TestController() }```

        - parameter method: The `Request.Method` that the action should be executed for.
        - parameter path: The HTTP path that the action can run at.
        - parameter action: The curried action to run on the provided type.
        - parameter factory: The closure to instantiate the controller type.
     */
    public final func add<ActionController>(
        _ method: Request.Method,
        path: String,
        action: (ActionController) -> (Request) throws -> ResponseRepresentable,
        makeControllerWith factory: () throws -> ActionController) {
        add(method, path: path) { request in
            let controller = try factory()
            return try action(controller)(request).makeResponse()
        }
    }

    /**
        Adds a route handler for an HTTP request using a given HTTP verb at a given
        path. The provided handler will be ran whenever the path is requested with
        the given method.

        - parameter method: The `Request.Method` that the handler should be executed for.
        - parameter path: The HTTP path that handler can run at.
        - parameter handler: The code to process the request with.
    */
    public final func add(_ method: Request.Method, path: String, handler: Route.Handler) {
        //Convert Route.Handler to Request.Handler
        var responder: Responder = Request.Handler { request in
            return try handler(request).makeResponse()
        }

        //Apply any scoped middlewares
        for middleware in self.scopedMiddleware {
            responder = middleware.chain(to: responder)
        }

        //Store the route for registering with Router later
        let host = scopedHost ?? "*"

        //Apply any scoped prefix
        var path = path
        if let prefix = scopedPrefix {
            path = prefix + "/" + path
        }

        let route = Route(host: host, method: method, path: path, responder: responder)
        self.routes.append(route)
    }

    /**
        Applies the middleware to the routes defined
        inside the closure. This method can be nested within
        itself safely.
    */
    public final func middleware(_ middleware: Middleware, handler: () -> ()) {
       self.middleware([middleware], handler: handler)
    }

    /**
        Applies the middleware to the routes defined
        inside the closure. This method can be nested within
        itself safely.
     */
    public final func middleware(_ middleware: [Middleware], handler: () -> ()) {
        let original = scopedMiddleware
        scopedMiddleware += middleware

        handler()

        scopedMiddleware = original
    }

    /**
        Create multiple routes with the same host
        without repeating yourself.
     */
    public final func host(_ host: String, handler: () -> Void) {
        let original = scopedHost
        scopedHost = host

        handler()

        scopedHost = original
    }

    /**
        Create multiple routes with the same base URL
        without repeating yourself.
    */
    public func group(_ prefix: String, handler: @noescape () -> Void) {
        let original = scopedPrefix

        //append original with a trailing slash
        if let original = original {
            scopedPrefix = original + "/" + prefix
        } else {
            scopedPrefix = prefix
        }

        handler()

        scopedPrefix = original
    }
}
