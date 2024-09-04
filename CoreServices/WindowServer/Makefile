MK_AUTO_OBJ=    yes
APP=	        WindowServer
.PATH:          ${.CURDIR}
SRCS=           WindowServer.m \
                BSDFramebuffer.m \
		WSInput.m \
		main.m
RESOURCES=	${.CURDIR}/Icon.png \
		${MAKEOBJDIR}/libinput.so.1 \
		${MAKEOBJDIR}/libinput.so \
		${MAKEOBJDIR}/libevdev.so.2 \
		${MAKEOBJDIR}/libevdev.so \
		#${MAKEOBJDIR}/seatd/seatd/seatd \
		#${MAKEOBJDIR}/seatd/libseat/libseat.so.0 \
		#${MAKEOBJDIR}/seatd/libseat/libseat.so \

MK_WERROR=	no
WARNS=	        1
SYSROOT=        --sysroot=${OBJTOP}/tmp -B${OBJTOP}/tmp/usr/bin
CFLAGS+=	-fobjc-arc -g -D__RAVYNOS__ -D__MACH__ -pthread -DDEBUG \
		-I${.CURDIR} -I${MAKEOBJDIR} -I${.CURDIR}/libinput/src \
		-I${SRCTOP}/Frameworks

LDFLAGS+=	-Wl,-R'$$ORIGIN/../Resources' -L${MAKEOBJDIR} \
		-L${OBJTOP}/Frameworks/Foundation/Foundation.framework \
		-L${OBJTOP}/Frameworks/CoreGraphics/CoreGraphics.framework \
		-L${OBJTOP}/Frameworks/CoreFoundation/CoreFoundation.framework \
		-L${OBJTOP}/Frameworks/Onyx2D/Onyx2D.framework \
                -Wl,-R/System/Library/Frameworks/OpenGL.framework/Versions/A \
                -Wl,-R/System/Library/Frameworks/Foundation.framework/Versions/A \
                -Wl,-R/System/Library/Frameworks/CoreGraphics.framework/Versions/A \
                -Wl,-R/System/Library/Frameworks/CoreFoundation.framework/Versions/A \
                -Wl,-R/System/Library/Frameworks/Onyx2D.framework/Versions/A \
		${OBJTOP}/tmp/lib/libutil.so.9 -L${MAKEOBJDIR}/libinput -linput \
		-ludev -lFoundation -lCoreGraphics -lCoreFoundation -lOnyx2D \
		-pthread -lobjc -lSystem -lm
#.export SYSROOT

SUBDIR+=        libevdev .WAIT
SUBDIR+=	mtdev .WAIT
SUBDIR+=        libinput .WAIT
#SUBDIR+=        seatd
#SUBDIR+=	gplv2/cairo

${MAKEOBJDIR}/Resources:
	cp -fv ${.CURDIR}/libinput/quirks/* ${APP_DIR}/Contents/Resources/
	${MAKE} -C ${.CURDIR}/libevdev tools
	${MAKE} -C ${.CURDIR}/libevdev tools-install APP_DIR=${APP_DIR}
	${MAKE} -C ${.CURDIR}/libinput tools
	${MAKE} -C ${.CURDIR}/libinput tools-install APP_DIR=${APP_DIR}

make-obj-dirs: .EXEC
	mkdir -p ${MAKEOBJDIR}
.for subdir in ${SUBDIR}
	mkdir -p ${MAKEOBJDIR}/${subdir}
.endfor
	mkdir -p ${MAKEOBJDIR}/LoginWindow
	mkdir -p ${MAKEOBJDIR}/SystemUIServer

clean: .PHONY
	rm -rf ${MAKEOBJDIR}

.include <sys.mk>
.include <bsd.subdir.mk>
.include <rvn.app.mk>

${OBJS}: ${MAKEOBJDIR}/Resources
