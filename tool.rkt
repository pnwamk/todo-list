#lang racket/gui
(require drracket/tool framework racket/runtime-path data/interval-map)

(provide tool@)

(define-runtime-path expansion-handler.rkt "expansion-handler.rkt")

(define tool@
  (unit
    (import drracket:tool^)
    (export drracket:tool-exports^)

    (struct goal-info (meta index) #:transparent)


    (define hole-finding-text-mixin
      (mixin (racket:text<%> drracket:unit:definitions-text<%>) ()
        (super-new)

        (inherit get-start-position set-position get-active-canvas scroll-to-position get-tab
                 position-line)

        (define (update-pos)
          (define pos (get-start-position))
          (define tab-info (hash-ref hole-info (get-tab) #f))
          (match (and hole-info
                      tab-info
                      (interval-map-ref tab-info pos #f))
            [#f (send (send (get-tab) get-frame) set-current-goal #f)]
            [(and g (goal-info _ i))
             (send (send (get-tab) get-frame) set-current-goal g)]))

        (define hole-info (make-hasheq))
        (define (set-hole-info! [info #f])
          (define tab (get-tab))
          (hash-set! hole-info tab
                     (and info (make-interval-map info)))
          (update-hole-info!))

        (define/public (update-hole-info!)
          (define tab (get-tab))
          (define frame (send tab get-frame))
          (let ([info (hash-ref hole-info tab #f)])
            (send frame set-goal-list (if info info (make-interval-map)))))

        (define/public (set-goals gs)
          (set-hole-info!
           (for/list ([g gs]
                      [i (in-range 10000)])
             (match-define `((,start . ,end) . ,goal) g)
             (cons (cons start end)
                   (goal-info (cdr g) i)))))

        (define/augment (after-set-position)
          (update-pos))

        (define/augment (after-insert start len)
          (define holes (hash-ref hole-info (get-tab) #f))
          (when holes
            (interval-map-expand! holes start (+ start len))
            (update-hole-info!)))

        (define/augment (after-delete start len)
          (define holes (hash-ref hole-info (get-tab) #f))
          (when holes
            (interval-map-contract! holes start (+ start len))
            (update-hole-info!)))))

    (define extra-panel-mixin
      (mixin (drracket:unit:frame<%>) ()

        (inherit get-definitions-text)

        (define/augment (on-tab-change from to)
          (send (get-definitions-text) update-hole-info!))

        (define goal-list-listeners (box null))
        (define/public (set-goal-list gs)
          (for ([l (unbox goal-list-listeners)])
            (send l on-new-goal-list gs)))

        (define current-goal-listeners (box null))
        (define/public (set-current-goal g)
          (for ([l (unbox current-goal-listeners)])
            (send l on-new-current-goal g)))

        (define/override (get-definitions/interactions-panel-parent)
          (define super-res (super get-definitions/interactions-panel-parent))
          (define new-panel
            (new (class panel:vertical-dragable%
                   (super-new)
                   (inherit change-children)
                   (define/public (on-new-goal-list gs)
                     (change-children
                      (lambda (subareas)
                        (append
                         (for/list ([area (in-list subareas)]
                                    #:when (not (eq? area hole-holder)))
                           area)
                         (if (dict-empty? gs)
                             null
                             (list hole-holder)))))))
                 [parent super-res]))
          (define hole-holder
            (new panel:horizontal-dragable% [parent new-panel] [style '(deleted)]))
          (define hole-list-box
            (new (class list-box%
                   (super-new)
                   (inherit append clear get-selection select set-selection)
                   (define/public (on-new-goal-list gs)
                     (clear)
                     (define defns (get-definitions-text))
                     (for ([(k g) (in-dict gs)])
                       (define line (send defns position-line (car k)))
                       (define col (- (car k) (send defns line-start-position line)))
                       (send hole-list-box append (number->string (add1 line)) (cons k g))
                       (define count (send hole-list-box get-number))
                       (send hole-list-box set-string (sub1 count) (number->string col) 1)
                       (send hole-list-box set-string (sub1 count) (format "~a" (goal-info-meta g)) 2)))
                   (define/public (on-new-current-goal g)
                     (if g
                         (set-selection (goal-info-index g))
                         (let ([sel (get-selection)])
                           (when sel (select sel #f))))))
                 [parent hole-holder]
                 [label #f]
                 [choices (list)]
                 [columns '("Line" "Col" "Goal")]
                 [style '(single column-headers)]
                 [callback (lambda (list-box evt)
                             (when (eqv? (send evt get-event-type) 'list-box)
                               (match (send list-box get-selections)
                                 [(list) (void)]
                                 [(list n)
                                  (match-define (cons (cons start end)
                                                      (goal-info meta _))
                                    (send list-box get-data n))
                                  (define defns (get-definitions-text))
                                  (queue-callback (thunk (send* defns
                                                           (set-position start end)
                                                           (scroll-to-position start #f end))
                                                         (define canvas (send defns get-active-canvas))
                                                         (when canvas (send canvas focus))))]
                                 [_ (void)])))]))

          (define p2
            (new group-box-panel%
                 [parent hole-holder]
                 [label "Details"]))
          (define details
            (new (class text-field%
                   (super-new)
                   (inherit set-value)
                   (define/public (on-new-current-goal g)
                     (if g
                         (set-value (format "Goal ~a:\n\t~a" (goal-info-index g) (goal-info-meta g)))
                         (set-value ""))))
                 [parent p2]
                 [label #f]
                 [style '(multiple)]))

          (set-box! goal-list-listeners (list hole-list-box new-panel))
          (set-box! current-goal-listeners (list hole-list-box details))

          new-panel)

        (super-new)))

    (define (phase1) (void))
    (define (phase2) (void))

    (drracket:get/extend:extend-definitions-text hole-finding-text-mixin)
    (drracket:get/extend:extend-unit-frame extra-panel-mixin)
    (drracket:module-language-tools:add-online-expansion-handler
     expansion-handler.rkt
     'handle-expansion
     (λ (text info)
       (send text set-goals info)))))


